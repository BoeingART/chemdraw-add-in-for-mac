-- SPDX-License-Identifier: Apache-2.0
on run argv
    set actionName to item 1 of argv
    tell application id "com.microsoft.Powerpoint"
        if actionName is "demo" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            set p to make new presentation
            set s to make new slide at end of p with properties {layout:slide layout blank}
            set pic to make new picture at end of s with properties {file name:item 2 of argv, left position:160, top:160}
            set name of pic to "ChemOffice Drawing:" & (item 5 of argv)
            set width of pic to 400
            set height of pic to 400 * ((item 6 of argv) as real)
            save p in POSIX file (item 4 of argv) as save as Open XML presentation
            activate
            return item 4 of argv
        else if actionName is "insert" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            set p to active presentation
            if full name of p is not (item 5 of argv) then error "The target PowerPoint document changed before paste"
            set s to slide of view of active window
            set pic to make new picture at end of s with properties {file name:item 2 of argv, left position:120, top:120}
            set name of pic to "ChemOffice Drawing:" & (item 4 of argv)
            set width of pic to 400
            set height of pic to 400 * ((item 6 of argv) as real)
            save p
            select pic
            activate
            return "inserted"
        else if actionName is "persist" then
            repeat with documentIndex from 1 to (count of presentations)
                set p to presentation documentIndex
                if full name of p is (item 2 of argv) then
                    save p
                    return "saved"
                end if
            end repeat
            error "Original PowerPoint presentation is not open"
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
            set pictureName to "ChemOffice Drawing:" & (item 3 of argv)
            set legacyName to "CFM1_" & (item 3 of argv)
            set dataName to "CFM_DATA_" & (item 3 of argv)
            set matches to {}
            repeat with slideIndex from 1 to (count of slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count of shapes of s)
                    set pic to shape pictureIndex of s
                    if name of pic is pictureName or name of pic is pictureName & "_pending" or name of pic is legacyName or name of pic is legacyName & "_pending" then set end of matches to {s, pic}
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
            if (count dataBoxes) > 1 then error "Ambiguous legacy ChemDraw source"
            if actionName is "payload" then
                if (count dataBoxes) is not 1 then error "Portable source is read from the saved graphic"
                return content of text range of text frame of item 1 of dataBoxes
            end if
            set pictureLeft to left position of oldPic
            set pictureTop to top of oldPic
            set pictureWidth to width of oldPic
            set pictureHeight to height of oldPic
            if (count of argv) >= 6 then set pictureHeight to pictureWidth * ((item 6 of argv) as real)
            set newPic to make new picture at end of s with properties {file name:item 4 of argv, left position:pictureLeft, top:pictureTop, width:pictureWidth, height:pictureHeight}
            set name of newPic to pictureName & "_pending"
            delete oldPic
            -- Deleting an earlier shape invalidates PowerPoint's indexed object reference.
            set pendingMatches to {}
            repeat with pictureIndex from 1 to (count of shapes of s)
                if name of shape pictureIndex of s is pictureName & "_pending" then set end of pendingMatches to pictureIndex as integer
            end repeat
            if (count pendingMatches) is not 1 then error "Cannot uniquely identify the inserted preview; source retained"
            set name of shape (item 1 of pendingMatches) of s to pictureName
            if (count dataBoxes) is 1 then delete shape dataName of s
            save p
            return "updated"
        else if actionName is "activate" then
            repeat with documentIndex from 1 to (count of presentations)
                set p to presentation documentIndex
                if full name of p is (item 2 of argv) then
                    set index of window (name of p) to 1
                    repeat with slideIndex from 1 to (count of slides of p)
                        set s to slide slideIndex of p
                        repeat with pictureIndex from 1 to (count of shapes of s)
                            if name of shape pictureIndex of s is "ChemOffice Drawing:" & (item 3 of argv) or name of shape pictureIndex of s is "CFM1_" & (item 3 of argv) then
                                set slide of view of active window to s
                                select shape pictureIndex of s
                                exit repeat
                            end if
                        end repeat
                    end repeat
                    exit repeat
                end if
            end repeat
            activate
            return "activated"
        end if
    end tell
end run
