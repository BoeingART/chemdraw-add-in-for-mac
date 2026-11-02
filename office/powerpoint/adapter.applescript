-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "ChemOffice Drawing:" & drawingID & ":" or tagText is "CFM1_" & drawingID
end matchesSource

on selectedOLETag()
    tell application id "com.microsoft.Powerpoint"
        set selectedShapes to shape range of selection of active window
        if (count shapes of selectedShapes) is not 1 then return ""
        set pic to shape 1 of selectedShapes
        if shape type of pic is not shape type embedded OLE control then return name of pic
        if name of pic starts with "ChemOffice Drawing:" then return name of pic
        return "ChemOffice OLE Selection:" & (slide ID of slide of view of active window as string) & ":" & name of pic
    end tell
end selectedOLETag

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
    if actionName is "document-status" then
        if application id "com.microsoft.Powerpoint" is not running then return "closed"
    end if
    tell application id "com.microsoft.Powerpoint"
        if actionName is "document-status" then
            set matchingCount to 0
            repeat with documentIndex from 1 to (count of presentations)
                if my matchesDocument(presentation documentIndex, item 2 of argv) then set matchingCount to matchingCount + 1
            end repeat
            if matchingCount is 0 then return "closed"
            if matchingCount is 1 then return "open"
            return "ambiguous"
        else if actionName is "demo" then
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
                return my selectedOLETag()
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
        else if actionName is "ole-active" then
            if my matchesDocument(active presentation, item 2 of argv) then return "yes"
            return "no"
        else if actionName is "ole-is-selected" then
            set p to my findDocument(item 2 of argv)
            if not my matchesDocument(active presentation, item 2 of argv) then return "no"
            try
                set selectedShapes to shape range of selection of document window 1 of p
                if (count shapes of selectedShapes) is 1 and name of shape 1 of selectedShapes is (item 3 of argv) then return "yes"
            end try
            return "no"
        else if actionName is "ole-debug" then
            return (full name of active presentation) & tab & ((count shapes of slide of view of active window) as string)
        else if actionName is "ole-window" then
            set p to my findDocument(item 2 of argv)
            set index of document window 1 of p to 1
            activate
            return caption of document window 1 of p
        else if actionName is "ole-copy" or actionName is "ole-claim" or actionName is "ole-kind" then
            set p to my findDocument(item 2 of argv)
            set targetText to item 3 of argv
            set matches to {}
            repeat with slideIndex from 1 to (count slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count shapes of s)
                    set pic to shape pictureIndex of s
                    set rawTag to "ChemOffice OLE Selection:" & (slide ID of s as string) & ":" & name of pic
                    if rawTag is targetText or name of pic is targetText or my matchesSource(name of pic, targetText) then set end of matches to {slideIndex as integer, pictureIndex as integer}
                end repeat
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to slide (item 1 of item 1 of matches) of p
            set pic to shape (item 2 of item 1 of matches) of s
            if actionName is "ole-kind" then
                if shape type of pic is shape type embedded OLE control then return "ole"
                return "picture"
            end if
            if shape type of pic is not shape type embedded OLE control then error "The selected shape is not an embedded OLE object"
            if actionName is "ole-copy" then
                set index of window (name of p) to 1
                if (slide ID of slide of view of document window 1 of p) is not (slide ID of s) then set slide of view of document window 1 of p to s
                activate
                return name of pic
            else
                set name of pic to item 4 of argv
            end if
            return "ok"
        else if actionName is "ole-insert-prepare" or actionName is "ole-update-prepare" then
            set p to my findDocument(item 2 of argv)
            set markerText to item 4 of argv
            set figureID to item 3 of argv
            if actionName is "ole-insert-prepare" then
                if not my matchesDocument(active presentation, item 2 of argv) then error "The target PowerPoint document changed before paste"
                set s to slide of view of active window
                set pictureLeft to 120
                set pictureTop to 120
                set pictureWidth to 400
                set pictureRotation to 0
                if (count shapes of s) is 0 then make new text box at end of s with properties {name:"CFM_OLE_ANCHOR:" & figureID, left position:0, top:0, width:1, height:1}
            else
                set matches to {}
                repeat with slideIndex from 1 to (count slides of p)
                    set candidateSlide to slide slideIndex of p
                    repeat with pictureIndex from 1 to (count shapes of candidateSlide)
                        set pic to shape pictureIndex of candidateSlide
                        if my matchesSource(name of pic, figureID) then set end of matches to {candidateSlide, pic}
                    end repeat
                end repeat
                if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
                set s to item 1 of item 1 of matches
                set oldPic to item 2 of item 1 of matches
                set pictureLeft to left position of oldPic
                set pictureTop to top of oldPic
                set pictureWidth to width of oldPic
                set pictureRotation to rotation of oldPic
            end if
            set index of window (name of p) to 1
            set slide of view of document window 1 of p to s
            activate
            return (slide ID of s as string) & tab & ((count of shapes of s) as string) & tab & (pictureLeft as string) & tab & (pictureTop as string) & tab & (pictureWidth as string) & tab & (pictureRotation as string)
        else if actionName is "ole-transport-close" then
            set p to my findDocument(item 2 of argv)
            close p saving no
            return "closed"
        else if actionName is "ole-target" or actionName is "ole-stage" then
            set p to my findDocument(item 2 of argv)
            set targetID to (item 6 of argv) as integer
            set foundSlides to {}
            repeat with slideIndex from 1 to (count slides of p)
                if slide ID of slide slideIndex of p is targetID then set end of foundSlides to slideIndex as integer
            end repeat
            if (count foundSlides) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to slide (item 1 of foundSlides) of p
            set previousCount to (item 7 of argv) as integer
            if actionName is "ole-target" then
                if (count shapes of s) is not previousCount then error "Original image identity changed; retained both versions"
                set index of window (name of p) to 1
                set slide of view of document window 1 of p to s
                activate
                repeat with pictureIndex from 1 to (count shapes of s)
                    set pic to shape pictureIndex of s
                    if my matchesSource(name of pic, item 3 of argv) then return name of pic
                end repeat
                if (count shapes of s) > 0 then return name of shape 1 of s
                error "Ambiguous or missing original PowerPoint figure"
            end if
            if (count shapes of s) is previousCount then return "waiting"
            if (count shapes of s) is not previousCount + 1 then error "PowerPoint did not insert exactly one OLE object; source retained"
            set newPic to shape (previousCount + 1) of s
            if shape type of newPic is not shape type embedded OLE control then
                delete newPic
                error "PowerPoint pasted a picture instead of an OLE object; please retry"
            end if
            set name of newPic to item 12 of argv
            set lock aspect ratio of newPic to false
            set left position of newPic to (item 8 of argv) as real
            set top of newPic to (item 9 of argv) as real
            set width of newPic to (item 10 of argv) as real
            set height of newPic to ((item 10 of argv) as real) * ((item 5 of argv) as real)
            if ((item 11 of argv) as real) is not 0 then set rotation of newPic to (item 11 of argv) as real
            return "staged"
        else if actionName is "ole-discard" then
            set p to my findDocument(item 2 of argv)
            if item 3 of argv does not start with "CFM_OLE_PENDING:" then error "Original image identity changed; retained both versions"
            repeat with slideIndex from 1 to (count slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from (count shapes of s) to 1 by -1
                    if name of shape pictureIndex of s is (item 3 of argv) then delete shape pictureIndex of s
                end repeat
            end repeat
            return "discarded"
        else if actionName is "ole-insert-commit" or actionName is "ole-update-commit" then
            set p to my findDocument(item 2 of argv)
            set newMatches to {}
            set oldMatches to {}
            repeat with slideIndex from 1 to (count slides of p)
                set s to slide slideIndex of p
                repeat with pictureIndex from 1 to (count shapes of s)
                    set pic to shape pictureIndex of s
                    if name of pic is (item 6 of argv) then set end of newMatches to {slideIndex as integer, pictureIndex as integer}
                    if my matchesSource(name of pic, item 3 of argv) then set end of oldMatches to {slideIndex as integer, pictureIndex as integer}
                end repeat
            end repeat
            if (count newMatches) is not 1 then error "Cannot uniquely identify the inserted preview; source retained"
            if actionName is "ole-update-commit" then
                if (count oldMatches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
                if (item 1 of item 1 of oldMatches) is not (item 1 of item 1 of newMatches) then error "Original image identity changed; retained both versions"
                delete shape (item 2 of item 1 of oldMatches) of slide (item 1 of item 1 of oldMatches) of p
            end if
            set s to slide (item 1 of item 1 of newMatches) of p
            set name of shape (item 6 of argv) of s to item 4 of argv
            repeat with pictureIndex from (count shapes of s) to 1 by -1
                if name of shape pictureIndex of s is "CFM_OLE_ANCHOR:" & (item 3 of argv) then delete shape pictureIndex of s
            end repeat
            return "committed"
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
                        set slide of view of document window 1 of p to s
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
