// SPDX-License-Identifier: Apache-2.0
import Cocoa
final class AcceptanceAutomation: NativeAutomation {
 var grantSeconds:TimeInterval = 0
 var savedPreview:Data?
 override func open(_ path:URL)throws {
  let source=try Data(contentsOf:path)
  try super.open(path)
  try require(try Data(contentsOf:path) == source,"Opening the editor changed the saved source")
  let app=try application()
  let modified=try script("tell application \(appleQuote(app.path)) to return modified of document (item 1 of argv)",[path.lastPathComponent])
  try require(modified == "false","Opening or scrolling the editor created an unsaved edit")
  print("PASS editor open and viewport preserve the saved source and clean document state")
 }
 override func captureEditableOLE(_ document:String,target:String,host:String)throws->Data? {
  let t=Date();defer{print("PHASE",host,"capture-with-clipboard",Date().timeIntervalSince(t))}
  return try super.captureEditableOLE(document,target:target,host:host)
 }
 override func transferOLE(_ action:String,arguments:[String],object:Data,vector:Data,host:String)throws {
  let t=Date();defer{print("PHASE",host,"transfer-with-clipboard",Date().timeIntervalSince(t))}
  try super.transferOLE(action,arguments:arguments,object:object,vector:vector,host:host)
 }
 override func windowlessPDFRenderer(_ app:ChemDrawApplication) throws -> URL? {
  if ProcessInfo.processInfo.environment["CFM_COMPAT_RENDER_TEST"] == "1" {return nil}
  return try super.windowlessPDFRenderer(app)
 }
 override func windowlessPDFSDK(_ app:ChemDrawApplication) -> URL? {
  if ProcessInfo.processInfo.environment["CFM_COMPAT_RENDER_TEST"] == "1" {return nil}
  return super.windowlessPDFSDK(app)
 }
 override func savedSnapshot(_ source:URL,_ image:URL) throws {
  savedPreview=nil
  let t=Date();defer{print("PHASE preview",Date().timeIntervalSince(t))};try super.savedSnapshot(source,image)
  savedPreview=try Data(contentsOf:image)
 }
 override func oleTransportDirectory(_ host:String) throws -> URL {
  if ProcessInfo.processInfo.environment["CFM_OLE_TEST_NATIVE_CACHE"] == "1" {return try super.oleTransportDirectory(host)}
  return root.appendingPathComponent("build/ole-inplace-acceptance/transports")
 }
 override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
  if ProcessInfo.processInfo.environment["CFM_OLE_TEST_NATIVE_CACHE"] != "1", host == "word", ["ole-import-stage","ole-update-stage"].contains(action) {
   let path=arguments[action == "ole-import-stage" ? 5:4],start=Date()
   try command(monitor,["--open-document-background",OfficeHost.word.bundle,path])
   _ = try super.office("ole-transport-close",host,[path])
   grantSeconds += Date().timeIntervalSince(start)
  }
  let t=Date();defer{print("PHASE",host,action,Date().timeIntervalSince(t))}
  return try super.office(action,host,arguments)
 }
}
@main struct LiveTests {
 static func main() {
  DispatchQueue(label:"acceptance").async {
   do {try run();exit(0)}catch{print("FAIL",error.localizedDescription);exit(1)}
  }
  dispatchMain()
 }
 static func run() throws {
  setbuf(stdout,nil)
  let project=URL(fileURLWithPath:CommandLine.arguments[1]), automation=AcceptanceAutomation(root:project)
  let mode=CommandLine.arguments.dropFirst(2).first ?? "performance"
  try require(["performance","identity","capability"].contains(mode),"Use performance, identity or capability mode")
  if mode == "capability" {
   let result=try automation.script("""
   tell application id "com.microsoft.Powerpoint"
    set p to make new presentation
    try
     set s to make new slide at end of p with properties {layout:slide layout blank}
     make new text box at end of s with properties {name:"one", left position:10, top:10, width:20, height:20}
     make new text box at end of s with properties {name:"two", left position:40, top:10, width:20, height:20}
     try
      set shape 1 of s to shape 2 of s
      set answerText to "PPT shape assignment accepted"
     on error messageText number errorNumber
      set answerText to "PPT shape assignment: " & messageText & " (" & errorNumber & ")"
     end try
     close p saving no
     return answerText
    on error messageText number errorNumber
     close p saving no
     error messageText number errorNumber
    end try
   end tell
   """,[])
   print(result);return
  }
  let run=project.appendingPathComponent("build/ole-inplace-acceptance/run-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:run,withIntermediateDirectories:true)
  let fixture=ProcessInfo.processInfo.environment["CFM_OLE_TEST_SOURCE"].map {URL(fileURLWithPath:$0)} ?? project.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx")
  let source=try Data(contentsOf:fixture)
  let hosts=ProcessInfo.processInfo.environment["CFM_OFFICE_TEST_HOSTS"]?.split(separator:",").map(String.init) ?? ["word","powerpoint"]
  let samples=Int(ProcessInfo.processInfo.environment["CFM_OLE_SAVE_SAMPLES"] ?? "3") ?? 3
  try require(!hosts.isEmpty && hosts.allSatisfy{["word","powerpoint"].contains($0)},"Choose word and/or powerpoint")
  try require((1...100).contains(samples),"Choose 1 to 100 saved revisions")
  for host in hosts {
   let bundle=host == "word" ? "com.microsoft.Word":"com.microsoft.Powerpoint"
   let close=host == "word" ? "document":"presentation"
   let documentCount=try automation.script("tell application id \"\(bundle)\" to return count \(close)s",[])
   print("OFFICE DOCUMENT COUNT",host,"before",documentCount)
   let create=host == "word" ? """
   tell application id "com.microsoft.Word"
    set d to make new document
    set content of text object of d to "Before" & return & "After" & return
    activate object d
    select (create range d start 7 end 7)
    return name of d
   end tell
   """ : """
   tell application id "com.microsoft.Powerpoint"
    set p to make new presentation
    make new slide at end of p with properties {layout:slide layout blank}
    activate
    return name of p
   end tell
   """
   let name=try automation.script(create,[])
   var currentName=name
   defer{
    _ = try? automation.script("tell application id \"\(bundle)\" to close \(close) (item 1 of argv) saving no",[currentName])
    let count=try? automation.script("tell application id \"\(bundle)\" to return count \(close)s",[])
    print("OFFICE DOCUMENT COUNT",host,"after",count ?? "unavailable")
   }
   let bridge=NativeBridge(root:run.appendingPathComponent(host),automation:automation)
   try bridge.prepare()
   let paste=run.appendingPathComponent(host+"-paste")
   try FileManager.default.createDirectory(at:paste,withIntermediateDirectories:true)
   try source.write(to:paste.appendingPathComponent("source.cdx"))
   var started=Date();try bridge.paste(host,snapshot:paste);print("TIMING",host,"paste",Date().timeIntervalSince(started))
   let tag=try automation.script(host == "word" ? "tell application id \"com.microsoft.Word\" to return alternative text of inline shape 1 of document (item 1 of argv)" : "tell application id \"com.microsoft.Powerpoint\" to return name of shape 1 of slide 1 of presentation (item 1 of argv)",[name])
   started=Date();try bridge.begin(host,tag:tag);print("TIMING",host,"open",Date().timeIntervalSince(started))
   let session=bridge.session!,path=URL(fileURLWithPath:session.path)
   defer {try? automation.closeWithoutActivation(path)}
   if let pause=Double(ProcessInfo.processInfo.environment["CFM_OLE_TEST_INSPECTION_PAUSE_SECONDS"] ?? ""),pause > 0 {
    try require(pause <= 60,"Inspection pause must be at most 60 seconds")
    print("INSPECTION",host,path.path,"pause seconds",pause)
    Thread.sleep(forTimeInterval:pause)
   }
   let app=try automation.application()
   // Identity acceptance deliberately saves only the document created above.
   // Keep it separate from the normal unsaved-document performance test.
   let baseline: [String:String]?
   var unstableIdentityKeys=Set<String>()
   if mode == "identity" {
    baseline=try identitySnapshot(automation,host:host,name:&currentName,id:session.id,
     file:run.appendingPathComponent(host+"-before."+(host == "word" ? "docx":"pptx")))
    print("IDENTITY",host,"before",baseline!)
    let unchanged=try identitySnapshot(automation,host:host,name:&currentName,id:session.id,
     file:run.appendingPathComponent(host+"-unchanged."+(host == "word" ? "docx":"pptx")))
    print("IDENTITY",host,"unchanged save control",unchanged)
    unstableIdentityKeys=Set(baseline!.keys.filter{baseline![$0] != unchanged[$0]})
    if !unstableIdentityKeys.isEmpty {
     identityControlFailures += 1
     print("INCONCLUSIVE",host,"native save changed identity fields",unstableIdentityKeys.sorted())
    }
   } else { baseline=nil }
   for i in 0..<samples {
    let editorSaveRequested=Date()
    _ = try automation.script("""
    tell application \(appleQuote(app.path))
     set d to document (item 1 of argv)
     set label size of d to (label size of d) + 1
     save d
    end tell
    """,[path.lastPathComponent])
    let saved=try Data(contentsOf:path)
    automation.grantSeconds=0
    started=Date();try bridge.save(SavedDrawingChange(id:session.id,path:session.path,source:saved))
    let elapsed=Date().timeIntervalSince(started)
    print("TIMING",host,"save",i+1,elapsed,"grant",automation.grantSeconds,"transaction",elapsed-automation.grantSeconds,"editor-save-and-bridge",Date().timeIntervalSince(editorSaveRequested))
    let object=try automation.captureOLE(session.document,target:session.id,host:host)
    let storage=try CompoundFile(object)
    try require(try storage.chemdrawSource() == saved,"Saved native OLE differs")
    let streams=try storage.rootStreams()
    guard let presentation=streams["\u{2}OlePres000"] else {throw ChemOfficeError("Saved native OLE lost its cached preview")}
    guard let expectedPreview=automation.savedPreview else {throw ChemOfficeError("Saved snapshot preview was not recorded")}
    try require(try storage.read(presentation) == ChemDrawOLE.presentation(expectedPreview),"Saved native OLE cached preview differs from the saved snapshot")
    print("PASS",host,"native OLE cached preview matches the saved snapshot",i+1)
    if let baseline {
     let after=try identitySnapshot(automation,host:host,name:&currentName,id:session.id,
      file:run.appendingPathComponent(host+"-after-\(i+1)."+(host == "word" ? "docx":"pptx")))
     print("IDENTITY",host,"after",i+1,after)
     let changed=baseline.keys.filter{!unstableIdentityKeys.contains($0) && baseline[$0] != after[$0]}.sorted()
     let retained=changed.isEmpty
     identityFailures += retained ? 0:1
     print(retained ? (unstableIdentityKeys.isEmpty ? "PASS":"INCONCLUSIVE"):"FAIL",host,"original Office OLE identity retention",i+1,"changed stable fields",changed)
    } else {
     try require(try automation.office("path",host,[session.document]).isEmpty,"Office test document was saved")
    }
   }
   print("PASS",host,"native paste, open and",samples,"OLE saves; source matches"+(mode == "identity" ? "; test snapshots saved":" and Office stays unsaved"))
  }
  if mode == "identity" {
   print("Identity evidence:",run.path)
   try require(identityFailures == 0 && identityControlFailures == 0,"Original Office OLE identity changed in \(identityFailures) saved revision(s); unstable native save controls: \(identityControlFailures)")
  }
 }
 static var identityFailures=0
 static var identityControlFailures=0
 static func identitySnapshot(_ automation:NativeAutomation,host:String,name:inout String,id:String,file:URL)throws->[String:String]{
  let bundle=host == "word" ? OfficeHost.word.bundle:OfficeHost.powerpoint.bundle
  let backing=file.deletingLastPathComponent().appendingPathComponent(host+"-live."+(host == "word" ? "docx":"pptx"))
  // Save As only once; subsequent controls and revisions use ordinary Save on
  // the same file, with read-only copies retained as evidence outside Office.
  if !FileManager.default.fileExists(atPath:backing.path) {
   if host == "word" {
    let source=try Data(contentsOf:automation.root.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx"))
    let vector=blankDrawingSVG(),object=try ChemDrawOLE.create(source:source,preview:renderPNG(vector))
    try ChemDrawOLE.wordTransport(object:object,vector:vector,marker:"identity-preflight").write(to:backing)
   } else {
    try FileManager.default.copyItem(at:automation.root.appendingPathComponent("assets/ole-transport.pptx"),to:backing)
   }
   try command(automation.monitor,["--open-document-background",bundle,backing.path])
   _ = try automation.office("ole-transport-close",host,[backing.path])
   let script=host == "word" ? """
  tell application id "com.microsoft.Word"
   set d to document (item 1 of argv)
   save as d file name (item 2 of argv) file format format document default
   return "saved"
  end tell
  """ : """
  tell application id "com.microsoft.Powerpoint"
   set p to presentation (item 1 of argv)
   save p in (POSIX file (item 2 of argv)) as save as Open XML presentation
   return "saved"
  end tell
  """
   _ = try automation.script(script,[name,backing.path])
   name=backing.lastPathComponent
  } else {
   let kind=host == "word" ? "document":"presentation"
   _ = try automation.script("""
   tell application id "\(bundle)"
    set d to \(kind) (item 1 of argv)
    set saved of d to false
    save d
   end tell
   """,[name])
  }
  try FileManager.default.copyItem(at:backing,to:file)
  let archive=try OfficeArchive(file)
  _ = try readSavedFigure(file.path,host:host,id:id)
  if host == "word" {
   let doc=try xml(archive.read("word/document.xml"))
   let objects=try nodes(doc,"//*[local-name()='OLEObject']")
   try require(objects.count == 1,"Identity fixture must contain one Word OLE object")
   let objectID=attribute(objects[0],"ObjectID"),shapeID=attribute(objects[0],"ShapeID")
   try require(!objectID.isEmpty && !shapeID.isEmpty,"Empty Word OLE identity")
   let anchor=try automation.script("tell application id \"com.microsoft.Word\" to return anchorID of inline shape 1 of document (item 1 of argv)",[name])
   return ["ObjectID":objectID,"ShapeID":shapeID,"anchorID":anchor]
  }
  let doc=try xml(archive.read("ppt/slides/slide1.xml"))
  let frames=try nodes(doc,"//*[local-name()='graphicFrame'][.//*[local-name()='oleObj']]")
  try require(frames.count == 1,"Identity fixture must contain one PowerPoint OLE frame")
  let properties=try nodes(frames[0],"./*[local-name()='nvGraphicFramePr']/*[local-name()='cNvPr']")
  try require(properties.count == 1,"Missing PowerPoint shape identity")
  let shapeID=attribute(properties[0],"id")
  try require(!shapeID.isEmpty,"Empty PowerPoint shape identity")
  return ["shapeID":shapeID]
 }
}
