-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "CFM1:" & drawingID & ":" or tagText starts with "CFM2:" & drawingID & ":"
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

on run argv
    set actionName to item 1 of argv
    tell application id "com.microsoft.Word"
        if actionName is "demo" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            set d to make new document
            set content of text object of d to "ChemOffice for Mac" & return & "Double-click the structure. Edit in ChemDraw. Close to return." & return & return
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
            if my documentPath(d) is not (item 5 of argv) then error "The target Word document changed before paste"
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
            set alternative text of pic to "ChemOffice Drawing:" & (item 4 of argv)
            set width of pic to 320
            set height of pic to 320 * ((item 6 of argv) as real)
            save d
            select text object of pic
            activate
            return "inserted"
        else if actionName is "selected" then
            if (count inline shapes of selection) is not 1 then return ""
            return alternative text of inline shape 1 of selection
        else if actionName is "context" then
            return my documentPath(active document)
        else if actionName is "save-for-paste" then
            set d to active document
            set currentPath to my documentPath(d)
            if currentPath starts with "/" then return currentPath
            set suggestedName to name of d
            if suggestedName does not end with ".docx" then set suggestedName to suggestedName & ".docx"
            activate
            try
                with timeout of 600 seconds
                    set chosenDrawingDocument to choose file name with prompt "Save this document to paste an editable ChemDraw drawing. The captured drawing will be inserted after saving." default name suggestedName
                end timeout
            on error number -128
                return ""
            end try
            -- Word's Save As expects a Mac file-name string. A POSIX string can
            -- silently save under its default name inside the Office container.
            set chosenDrawingDocumentName to chosenDrawingDocument as text
            save as d file name chosenDrawingDocumentName file format format document default
            if my documentPath(d) is not (POSIX path of chosenDrawingDocument) then error "Word did not save to the selected location; captured chemistry was retained"
            return my documentPath(d)
        else if actionName is "persist" then
            repeat with documentIndex from 1 to (count of documents)
                set d to document documentIndex
                if my documentPath(d) is (item 2 of argv) then
                    save d
                    return "saved"
                end if
            end repeat
            error "Original Word document is not open"
        else if actionName is "payload" then
            set prefixText to "CFM1:" & (item 3 of argv) & ":"
            set matchingPayloads to {}
            repeat with documentIndex from 1 to (count of documents)
                set d to document documentIndex
                if my documentPath(d) is (item 2 of argv) then
                    repeat with pictureIndex from 1 to (count of inline shapes of d)
                        set pic to inline shape pictureIndex of d
                        if my matchesSource(alternative text of pic, item 3 of argv) then set end of matchingPayloads to alternative text of pic
                    end repeat
                end if
            end repeat
            if (count matchingPayloads) is not 1 then error "Expected exactly one matching Word figure"
            return item 1 of matchingPayloads
        else if actionName is "update" then
            set prefixText to "CFM1:" & (item 3 of argv) & ":"
            set matchingDocs to {}
            repeat with documentIndex from 1 to (count of documents)
                if my documentPath(document documentIndex) is (item 2 of argv) then set end of matchingDocs to document documentIndex
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
            set alternative text of newPic to "ChemOffice Drawing:" & (item 3 of argv)
            set width of newPic to w
            set height of newPic to h
            if alternative text of inline shape originalIndex of d is not oldTag then error "Original image identity changed; retained both versions"
            delete inline shape originalIndex of d
            if (count of inline shapes of d) is not originalCount then error "Word picture count changed unexpectedly"
            save d
            return "updated"
        else if actionName is "activate" then
            repeat with documentIndex from 1 to (count of documents)
                set d to document documentIndex
                try
                    set pathText to POSIX path of ((full name of d) as alias)
                on error
                    set pathText to ""
                end try
                if pathText is (item 2 of argv) then
                    activate object d
                    repeat with pictureIndex from 1 to (count of inline shapes of d)
                        if my matchesSource(alternative text of inline shape pictureIndex of d, item 3 of argv) then
                            select text object of inline shape pictureIndex of d
                            exit repeat
                        end if
                    end repeat
                    exit repeat
                end if
            end repeat
            activate
            return "activated"
        end if
    end tell
end run
