-- SPDX-License-Identifier: Apache-2.0
on run argv
    set actionName to item 1 of argv
    tell application id "com.microsoft.Powerpoint"
        if actionName is "demo" then
            set p to make new presentation
            set s to make new slide at end of p with properties {layout:slide layout blank}
            set pic to make new picture at end of s with properties {file name:item 2 of argv, left position:160, top:160, width:400, height:180}
            set name of pic to "CFM1_" & (item 5 of argv)
            -- Prototype storage: source travels in a hidden text box on the same slide.
            set dataBox to make new text box at end of s with properties {left position:-1000, top:0, width:1, height:1}
            set name of dataBox to "CFM_DATA_" & (item 5 of argv)
            set content of text range of text frame of dataBox to item 3 of argv
            set visible of dataBox to false
            save p in POSIX file (item 4 of argv) as save as Open XML presentation
            activate
            return item 4 of argv
        else if actionName is "selected" then
            try
                set selectedShapes to shape range of selection of active window
                if (count shapes of selectedShapes) is not 1 then return ""
                return name of shape 1 of selectedShapes
            on error
                return ""
            end try
        else if actionName is "context" then
            return full name of active presentation
        else if actionName is "payload" or actionName is "update" then
            set docs to {}
            repeat with documentIndex from 1 to (count of presentations)
                if full name of presentation documentIndex is (item 2 of argv) then set end of docs to presentation documentIndex
            end repeat
            if (count docs) is not 1 then error "Original PowerPoint presentation is not open"
            set p to item 1 of docs
            set pictureName to "CFM1_" & (item 3 of argv)
            set dataName to "CFM_DATA_" & (item 3 of argv)
            set matches to {}
            repeat with slideIndex from 1 to (count of slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count of shapes of s)
                    set pic to shape pictureIndex of s
                    if name of pic is pictureName or name of pic is pictureName & "_pending" then set end of matches to {s, pic}
                end repeat
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to item 1 of item 1 of matches
            set oldPic to item 2 of item 1 of matches
            if actionName is "update" then set name of oldPic to pictureName
            set dataBoxes to {}
            repeat with pictureIndex from 1 to (count of shapes of s)
                if name of shape pictureIndex of s is dataName then set end of dataBoxes to shape pictureIndex of s
            end repeat
            if (count dataBoxes) is not 1 then error "Missing embedded ChemDraw source"
            set dataBox to item 1 of dataBoxes
            if actionName is "payload" then return content of text range of text frame of dataBox
            set pictureLeft to left position of oldPic
            set pictureTop to top of oldPic
            set pictureWidth to width of oldPic
            set pictureHeight to height of oldPic
            set newPic to make new picture at end of s with properties {file name:item 4 of argv, left position:pictureLeft, top:pictureTop, width:pictureWidth, height:pictureHeight}
            set name of newPic to pictureName & "_pending"
            set content of text range of text frame of dataBox to item 5 of argv
            delete oldPic
            -- Deleting an earlier shape invalidates PowerPoint's indexed object reference.
            set pendingMatches to {}
            repeat with pictureIndex from 1 to (count of shapes of s)
                if name of shape pictureIndex of s is pictureName & "_pending" then set end of pendingMatches to pictureIndex as integer
            end repeat
            if (count pendingMatches) is not 1 then error "Cannot uniquely identify the inserted preview; source retained"
            set name of shape (item 1 of pendingMatches) of s to pictureName
            save p
            return "updated"
        else if actionName is "activate" then
            activate
            return "activated"
        end if
    end tell
end run
