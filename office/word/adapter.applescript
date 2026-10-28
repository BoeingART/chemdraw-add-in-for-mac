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
    return my documentPath(d) is referenceText
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
            return my contextID(active document, item 2 of argv)
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
