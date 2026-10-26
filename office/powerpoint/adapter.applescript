-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "ChemOffice Drawing:" & drawingID & ":" or tagText is "CFM1_" & drawingID
end matchesSource

on existingID(p)
    tell application id "com.microsoft.Powerpoint"
        repeat with shapeIndex from 1 to (count of shapes of slide master of p)
            set markerName to name of shape shapeIndex of slide master of p
            if markerName starts with "CFM_DOCUMENT_ID:" then return text 17 thru -1 of markerName
        end repeat
        return ""
    end tell
end existingID

on matchesDocument(p, referenceText)
    if referenceText starts with "cfm-document:" then return "cfm-document:" & my existingID(p) is referenceText
    tell application id "com.microsoft.Powerpoint" to return full name of p is referenceText
end matchesDocument

on findDocument(referenceText)
    tell application id "com.microsoft.Powerpoint"
        set matches to {}
        repeat with documentIndex from 1 to (count of presentations)
            set p to presentation documentIndex
            if my matchesDocument(p, referenceText) then set end of matches to p
        end repeat
        if (count matches) is not 1 then error "The original PowerPoint presentation is no longer uniquely available"
        return item 1 of matches
    end tell
end findDocument

on contextID(p, candidateID)
    tell application id "com.microsoft.Powerpoint"
        set identityText to my existingID(p)
        set matches to 0
        if identityText is not "" then
            repeat with documentIndex from 1 to (count of presentations)
                if my existingID(presentation documentIndex) is identityText then set matches to matches + 1
            end repeat
        end if
        if matches > 1 then error "Close the other copy of this PowerPoint presentation before editing its drawing"
        if identityText is "" then
            make new text box at end of slide master of p with properties {name:"CFM_DOCUMENT_ID:" & candidateID, visible:false, left position:0, top:0, width:1, height:1}
            set identityText to candidateID
        end if
        return "cfm-document:" & identityText
    end tell
end contextID

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
            if not my matchesDocument(p, item 5 of argv) then error "The target PowerPoint document changed before paste"
            set s to slide of view of active window
            set pic to make new picture at end of s with properties {file name:item 2 of argv, left position:120, top:120}
            set name of pic to item 3 of argv
            set width of pic to 400
            set height of pic to 400 * ((item 6 of argv) as real)
            select pic
            activate
            return "inserted"
        else if actionName is "selected" then
            try
                set selectedShapes to shape range of selection of active window
                if (count shapes of selectedShapes) is not 1 then return ""
                return name of shape 1 of selectedShapes
            on error
                return ""
            end try
        else if actionName is "context" then
            return my contextID(active presentation, item 2 of argv)
        else if actionName is "path" then
            set p to my findDocument(item 2 of argv)
            set pathText to full name of p
            if pathText starts with "/" then return pathText
            return ""
        else if actionName is "payload" or actionName is "inspect" or actionName is "update" then
            set docs to {}
            repeat with documentIndex from 1 to (count of presentations)
                if my matchesDocument(presentation documentIndex, item 2 of argv) then set end of docs to presentation documentIndex
            end repeat
            if (count docs) is not 1 then error "Original PowerPoint presentation is not open"
            set p to item 1 of docs
            set dataName to "CFM_DATA_" & (item 3 of argv)
            set matches to {}
            repeat with slideIndex from 1 to (count of slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count of shapes of s)
                    set pic to shape pictureIndex of s
                    if my matchesSource(name of pic, item 3 of argv) then set end of matches to {s, pic}
                end repeat
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to item 1 of item 1 of matches
            set oldPic to item 2 of item 1 of matches
            set dataBoxes to {}
            repeat with pictureIndex from 1 to (count of shapes of s)
                if name of shape pictureIndex of s is dataName then set end of dataBoxes to shape pictureIndex of s
            end repeat
            if (count dataBoxes) > 1 then error "Ambiguous legacy ChemDraw source"
            if actionName is "payload" then
                if (count dataBoxes) is 1 then return content of text range of text frame of item 1 of dataBoxes
                return name of oldPic
            end if
            if actionName is "inspect" then return (name of oldPic) & tab & (width of oldPic as string) & tab & (height of oldPic as string)
            set pictureLeft to left position of oldPic
            set pictureTop to top of oldPic
            set pictureWidth to width of oldPic
            set pictureHeight to height of oldPic
            if (count of argv) >= 6 then set pictureHeight to pictureWidth * ((item 6 of argv) as real)
            set newPic to make new picture at end of s with properties {file name:item 4 of argv, left position:pictureLeft, top:pictureTop, width:pictureWidth, height:pictureHeight}
            set name of newPic to (item 5 of argv) & "_pending"
            delete oldPic
            -- Deleting an earlier shape invalidates PowerPoint's indexed object reference.
            set pendingMatches to {}
            repeat with pictureIndex from 1 to (count of shapes of s)
                if name of shape pictureIndex of s is (item 5 of argv) & "_pending" then set end of pendingMatches to pictureIndex as integer
            end repeat
            if (count pendingMatches) is not 1 then error "Cannot uniquely identify the inserted preview; source retained"
            set name of shape (item 1 of pendingMatches) of s to item 5 of argv
            if (count dataBoxes) is 1 then delete shape dataName of s
            return "updated"
        else if actionName is "activate" then
            set p to my findDocument(item 2 of argv)
            set index of window (name of p) to 1
            repeat with slideIndex from 1 to (count of slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count of shapes of s)
                    if my matchesSource(name of shape pictureIndex of s, item 3 of argv) then
                        set slide of view of active window to s
                        select shape pictureIndex of s
                        exit repeat
                    end if
                end repeat
            end repeat
            activate
            return "activated"
        end if
    end tell
end run
