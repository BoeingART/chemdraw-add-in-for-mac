-- SPDX-License-Identifier: Apache-2.0
on run argv
    set actionName to item 1 of argv
    tell application id "com.microsoft.Word"
        if actionName is "demo" then
            set d to make new document
            set content of text object of d to "ChemOffice for Mac" & return & "Double-click the structure. Edit in ChemDraw. Close to return." & return & return
            set pic to make new inline picture at end of text object of d with properties {file name:item 2 of argv, link to file:false, save with document:true}
            set alternative text of pic to item 3 of argv
            set originalWidth to width of pic
            set originalHeight to height of pic
            set width of pic to 320
            set height of pic to originalHeight * 320 / originalWidth
            save as d file name (item 4 of argv) file format format document default
            activate
            return item 4 of argv
        else if actionName is "selected" then
            if (count inline shapes of selection) is not 1 then return ""
            return alternative text of inline shape 1 of selection
        else if actionName is "context" then
            return POSIX path of ((full name of active document) as alias)
        else if actionName is "payload" then
            set prefixText to "CFM1:" & (item 3 of argv) & ":"
            set matchingPayloads to {}
            repeat with documentIndex from 1 to (count of documents)
                set d to document documentIndex
                if POSIX path of ((full name of d) as alias) is (item 2 of argv) then
                    repeat with pictureIndex from 1 to (count of inline shapes of d)
                        set pic to inline shape pictureIndex of d
                        if alternative text of pic starts with prefixText then set end of matchingPayloads to alternative text of pic
                    end repeat
                end if
            end repeat
            if (count matchingPayloads) is not 1 then error "Expected exactly one matching Word figure"
            return item 1 of matchingPayloads
        else if actionName is "update" then
            set prefixText to "CFM1:" & (item 3 of argv) & ":"
            set matchingDocs to {}
            repeat with documentIndex from 1 to (count of documents)
                if POSIX path of ((full name of document documentIndex) as alias) is (item 2 of argv) then set end of matchingDocs to document documentIndex
            end repeat
            if (count matchingDocs) is not 1 then error "Original Word document is not open"
            set d to item 1 of matchingDocs
            set matches to {}
            repeat with pictureIndex from 1 to (count of inline shapes of d)
                set pic to inline shape pictureIndex of d
                if alternative text of pic starts with prefixText then set end of matches to pic
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original Word figure"
            set oldPic to item 1 of matches
            set oldTag to alternative text of oldPic
            set w to width of oldPic
            set h to height of oldPic
            set newPic to make new inline picture at text object of oldPic with properties {file name:item 4 of argv, link to file:false, save with document:true}
            set alternative text of newPic to item 5 of argv
            set width of newPic to w
            set height of newPic to h
            -- Identify the old object by its complete previous payload, never by a shifted index.
            repeat with i from (count inline shapes of d) to 1 by -1
                if alternative text of inline shape i of d is oldTag and oldTag is not (item 5 of argv) then delete inline shape i of d
            end repeat
            save d
            return "updated"
        else if actionName is "activate" then
            activate
            return "activated"
        end if
    end tell
end run
