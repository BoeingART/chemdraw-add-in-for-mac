-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "ChemOffice Drawing:" & drawingID & ":" or tagText starts with "CFM1:" & drawingID & ":" or tagText starts with "CFM2:" & drawingID & ":"
end matchesSource

on documentPath(d)
    tell application id "com.microsoft.Word"
        try
            return POSIX path of ((full name of d) as alias)
        on error
            return ""
        end try
    end tell
end documentPath

on existingID(d)
    tell application id "com.microsoft.Word"
        try
            return value of custom document property "ChemOfficeDocumentID" of d
        on error
            return ""
        end try
    end tell
end existingID

on matchesDocument(d, referenceText)
    if referenceText starts with "cfm-document:" then return "cfm-document:" & my existingID(d) is referenceText
    tell application id "com.microsoft.Word" to return my documentPath(d) is referenceText or name of d is referenceText
end matchesDocument

-- Lifecycle checks must propagate failed reads instead of interpreting them
-- as an absent document. Enumerate properties so a missing ID is distinct
-- from a failed property request.
on matchesOpenDocument(d, referenceText)
    tell application id "com.microsoft.Word"
        if referenceText starts with "cfm-document:" then
            repeat with propertyIndex from 1 to (count of custom document properties of d)
                set identityProperty to custom document property propertyIndex of d
                if name of identityProperty is "ChemOfficeDocumentID" then return "cfm-document:" & (value of identityProperty) is referenceText
            end repeat
            return false
        end if
        return POSIX path of ((full name of d) as alias) is referenceText
    end tell
end matchesOpenDocument

on findDocument(referenceText)
    tell application id "com.microsoft.Word"
        set matches to {}
        repeat with documentIndex from 1 to (count of documents)
            set d to document documentIndex
            if my matchesDocument(d, referenceText) then set end of matches to d
        end repeat
        if (count matches) is not 1 then error "The original Word document is no longer uniquely available"
        return item 1 of matches
    end tell
end findDocument

on contextID(d, candidateID)
    tell application id "com.microsoft.Word"
        set identityText to my existingID(d)
        set matches to 0
        if identityText is not "" then
            repeat with documentIndex from 1 to (count of documents)
                if my existingID(document documentIndex) is identityText then set matches to matches + 1
            end repeat
        end if
        if matches > 1 then error "Close the other copy of this Word document before editing its drawing"
        if identityText is "" then
            make new custom document property at d with properties {name:"ChemOfficeDocumentID", value:candidateID, document property type:string, link to content:false}
            set identityText to candidateID
        end if
        return "cfm-document:" & identityText
    end tell
end contextID

on findFigure(d, targetText)
    tell application id "com.microsoft.Word"
        set matches to {}
        repeat with pictureIndex from 1 to count inline shapes of d
            set pic to inline shape pictureIndex of d
            set tagText to alternative text of pic
            set rawTag to "ChemOffice OLE Selection:" & (start of content of text object of pic as string)
            if tagText is targetText or my matchesSource(tagText, targetText) or rawTag is targetText then set end of matches to pictureIndex as integer
        end repeat
        if (count matches) is not 1 then error "Expected exactly one matching Word figure"
        return inline shape (item 1 of matches) of d
    end tell
end findFigure

on objectStart(d, pic)
    tell application id "com.microsoft.Word"
        set pictureStart to start of content of text object of pic
        if inline shape type of pic is inline shape embedded oleobject then
            repeat with fieldIndex from 1 to count fields of d
                set f to field fieldIndex of d
                if field type of f is field embed then
                    if start of content of result range of f is pictureStart then return (start of content of field code of f) - 1
                end if
            end repeat
            error "Expected exactly one matching Word figure"
        end if
        return pictureStart
    end tell
end objectStart

on run argv
    set actionName to item 1 of argv
    if actionName is "document-status" then
        if application id "com.microsoft.Word" is not running then return "closed"
    end if
    tell application id "com.microsoft.Word"
        if actionName is "document-status" then
            set matchingCount to 0
            repeat with documentIndex from 1 to (count of documents)
                if my matchesOpenDocument(document documentIndex, item 2 of argv) then set matchingCount to matchingCount + 1
            end repeat
            if matchingCount is 0 then return "closed"
            if matchingCount is 1 then return "open"
            return "ambiguous"
        else if actionName is "demo" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            set d to make new document
            set content of text object of d to "ChemDraw Add-in for Mac" & return & "Double-click the structure. Edit in ChemDraw. Close to return." & return & return
            make new inline picture at end of text object of d with properties {file name:item 2 of argv, link to file:false, save with document:true}
            set pic to inline shape (count of inline shapes of d) of d
            set alternative text of pic to "ChemOffice Drawing:" & (item 5 of argv)
            set width of pic to 320
            set height of pic to 320 * ((item 6 of argv) as real)
            set demoDocumentName to (POSIX file (item 4 of argv)) as text
            save as d file name demoDocumentName file format format document default
            activate
            return item 4 of argv
        else if actionName is "insert" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            set d to active document
            if not my matchesDocument(d, item 5 of argv) then error "The target Word document changed before paste"
            set insertionRange to collapse range (text object of selection) direction collapse end
            set insertionStart to start of content of insertionRange
            set insertedIndex to 1
            set originalCount to count of inline shapes of d
            repeat with pictureIndex from 1 to originalCount
                if start of content of text object of inline shape pictureIndex of d < insertionStart then set insertedIndex to insertedIndex + 1
            end repeat
            make new inline picture at insertionRange with properties {file name:item 2 of argv, link to file:false, save with document:true}
            if (count of inline shapes of d) is not originalCount + 1 then error "Unexpected Word paste result; kept the captured source"
            -- SVG insertion returns an unusable inline-picture specifier in Word.
            set pic to inline shape insertedIndex of d
            set alternative text of pic to item 3 of argv
            set width of pic to 320
            set height of pic to 320 * ((item 6 of argv) as real)
            select text object of pic
            activate
            return "inserted"
        else if actionName is "selected" then
            if (count inline shapes of selection) is not 1 then return ""
            return alternative text of inline shape 1 of selection
        else if actionName is "context" then
            if (count argv) > 2 then return my contextID(my findDocument(item 3 of argv), item 2 of argv)
            return my contextID(active document, item 2 of argv)
        else if actionName is "reference" then
            set documentPath to my documentPath(active document)
            if documentPath is not "" then return documentPath
            return name of active document
        else if actionName is "ole-transport-close" then
            close (my findDocument(item 2 of argv)) saving no
            return "closed"
        else if actionName is "ole-kind" or actionName is "ole-capture" or actionName is "ole-claim" then
            set d to my findDocument(item 2 of argv)
            set pic to my findFigure(d, item 3 of argv)
            if actionName is "ole-claim" then
                set alternative text of pic to item 4 of argv
                return "claimed"
            end if
            if inline shape type of pic is not inline shape embedded oleobject then return "picture"
            if actionName is "ole-kind" then return "ole"
            copy object text object of pic
            return "copied"
        else if actionName is "ole-insert-prepare" or actionName is "ole-update-prepare" then
            set d to my findDocument(item 2 of argv)
            set originalMarker to "-"
            if actionName is "ole-insert-prepare" then
                if not my matchesDocument(active document, item 2 of argv) then error "The target Word document changed before paste"
                set insertionRange to collapse range (text object of selection) direction collapse end
                set insertionStart to start of content of insertionRange
                -- A selected OLE result is inside its field. Insert a new copy
                -- after the entire field instead of nesting it in that result.
                repeat with fieldIndex from 1 to count fields of d
                    set f to field fieldIndex of d
                    if field type of f is field embed then
                        if insertionStart > (start of content of field code of f) - 1 and insertionStart <= end of content of result range of f then set insertionStart to (end of content of result range of f) + 1
                    end if
                end repeat
                set pictureWidth to 320
            else
                set pic to my findFigure(d, item 3 of argv)
                set insertionStart to my objectStart(d, pic)
                set pictureWidth to width of pic
                set originalMarker to alternative text of pic
            end if
            set insertionRange to create range d start insertionStart end insertionStart
            make new bookmark at d with properties {name:item 6 of argv, text object:insertionRange}
            return ((count inline shapes of d) as string) & tab & (pictureWidth as string) & tab & originalMarker
        else if actionName is "ole-import-stage" then
            set d to my findDocument(item 2 of argv)
            set insertionRange to text object of bookmark (item 6 of argv) of d
            if (count inline shapes of d) is not (item 10 of argv) as integer then error "Original image identity changed; retained both versions"
            insert file at insertionRange file name (item 7 of argv) file range (item 8 of argv) confirm conversions false link false
            if (count inline shapes of d) is not ((item 10 of argv) as integer) + 1 then error "Unexpected Word insertion result; retained both versions"
            set pic to my findFigure(d, item 9 of argv)
            if inline shape type of pic is not inline shape embedded oleobject then error "Word inserted a picture instead of an OLE object"
            set lock aspect ratio of pic to false
            set width of pic to (item 11 of argv) as real
            set height of pic to ((item 11 of argv) as real) * ((item 5 of argv) as real)
            copy object text object of pic
            return "staged"
        else if actionName is "ole-insert-commit" or actionName is "ole-update-commit" then
            set d to my findDocument(item 2 of argv)
            set newPic to my findFigure(d, item 6 of argv)
            if inline shape type of newPic is not inline shape embedded oleobject then error "Expected exactly one matching Word figure"
            if actionName is "ole-update-commit" then
                set oldPic to my findFigure(d, item 3 of argv)
                if alternative text of oldPic is not item 8 of argv then error "Original image identity changed; retained both versions"
                delete oldPic
            end if
            set newPic to my findFigure(d, item 6 of argv)
            set alternative text of newPic to item 4 of argv
            if exists bookmark (item 7 of argv) of d then delete bookmark (item 7 of argv) of d
            return (alternative text of newPic) & tab & (width of newPic as string) & tab & (height of newPic as string)
        else if actionName is "ole-discard" then
            set d to my findDocument(item 2 of argv)
            if item 3 of argv does not start with "CFM_OLE_PENDING:" then error "Original image identity changed; retained both versions"
            repeat with pictureIndex from count inline shapes of d to 1 by -1
                if alternative text of inline shape pictureIndex of d is item 3 of argv then delete inline shape pictureIndex of d
            end repeat
            if (count argv) > 3 then
                if exists bookmark (item 4 of argv) of d then delete bookmark (item 4 of argv) of d
            end if
            return "discarded"
        else if actionName is "path" then
            return my documentPath(my findDocument(item 2 of argv))
        else if actionName is "payload" or actionName is "inspect" then
            set d to my findDocument(item 2 of argv)
            set matchingPayloads to {}
            repeat with pictureIndex from 1 to (count of inline shapes of d)
                set pic to inline shape pictureIndex of d
                if my matchesSource(alternative text of pic, item 3 of argv) then
                    set resultText to alternative text of pic
                    if actionName is "inspect" then set resultText to resultText & tab & (width of pic as string) & tab & (height of pic as string)
                    set end of matchingPayloads to resultText
                end if
            end repeat
            if (count matchingPayloads) is not 1 then error "Expected exactly one matching Word figure"
            return item 1 of matchingPayloads
        else if actionName is "update" then
            set matchingDocs to {}
            repeat with documentIndex from 1 to (count of documents)
                if my matchesDocument(document documentIndex, item 2 of argv) then set end of matchingDocs to document documentIndex
            end repeat
            if (count matchingDocs) is not 1 then error "Original Word document is not open"
            set d to item 1 of matchingDocs
            set matches to {}
            repeat with pictureIndex from 1 to (count of inline shapes of d)
                set pic to inline shape pictureIndex of d
                if my matchesSource(alternative text of pic, item 3 of argv) then set end of matches to pictureIndex as integer
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original Word figure"
            set originalIndex to item 1 of matches
            set originalCount to count of inline shapes of d
            set oldPic to inline shape originalIndex of d
            set oldTag to alternative text of oldPic
            set w to width of oldPic
            set h to height of oldPic
            if (count of argv) >= 6 then set h to w * ((item 6 of argv) as real)
            make new inline picture at text object of oldPic with properties {file name:item 4 of argv, link to file:false, save with document:true}
            if (count of inline shapes of d) is not originalCount + 1 then error "Unexpected Word insertion result; retained both versions"
            -- Word's returned inline-picture reference can resolve to the old image.
            -- Insertion at its range places the new image immediately after it.
            set newPic to inline shape (originalIndex + 1) of d
            set alternative text of newPic to item 5 of argv
            set width of newPic to w
            set height of newPic to h
            if alternative text of inline shape originalIndex of d is not oldTag then error "Original image identity changed; retained both versions"
            delete inline shape originalIndex of d
            if (count of inline shapes of d) is not originalCount then error "Word picture count changed unexpectedly"
            return "updated"
        else if actionName is "activate" then
            set d to my findDocument(item 2 of argv)
            activate object d
            repeat with pictureIndex from 1 to (count of inline shapes of d)
                if my matchesSource(alternative text of inline shape pictureIndex of d, item 3 of argv) then
                    select text object of inline shape pictureIndex of d
                    exit repeat
                end if
            end repeat
            activate
            return "activated"
        end if
    end tell
end run
