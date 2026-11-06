-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "ChemOffice Drawing:" & drawingID & ":" or tagText is "CFM1_" & drawingID
end matchesSource

on selectedOLETag()
    tell application id "com.microsoft.Powerpoint"
        set selectedShapes to shape range of selection of active window
        if (count shapes of selectedShapes) is not 1 then return ""
        set pic to shape 1 of selectedShapes
        if shape type of pic is shape type group then
            if name of pic starts with "ChemOffice Drawing:" then return name of pic
            return "ChemOffice OLE Selection:" & (slide ID of slide of view of active window as string) & ":group:" & name of pic
        end if
        if shape type of pic is not shape type embedded OLE control then return name of pic
        if name of pic starts with "ChemOffice Drawing:" then return name of pic
        return "ChemOffice OLE Selection:" & (slide ID of slide of view of active window as string) & ":" & name of pic
    end tell
end selectedOLETag

on existingID(p)
    tell application id "com.microsoft.Powerpoint"
        set markerNames to get name of every shape of slide master of p
        repeat with markerName in markerNames
            if markerName starts with "CFM_DOCUMENT_ID:" then return text 17 thru -1 of markerName
        end repeat
        return ""
    end tell
end existingID

on hintSeparator(valueText)
    return offset of "|" in valueText
end hintSeparator

on matchesDocument(p, referenceText)
    if referenceText starts with "cfm-document:" then
        set boundary to my hintSeparator(referenceText)
        if boundary > 0 then set referenceText to text 1 thru (boundary - 1) of referenceText
        return "cfm-document:" & my existingID(p) is referenceText
    end if
    tell application id "com.microsoft.Powerpoint" to return full name of p is referenceText
end matchesDocument

on documentStamp()
    tell application id "com.microsoft.Powerpoint" to set paths to get full name of every presentation
    set stampText to ""
    repeat with pathText in paths
        set pathValue to pathText as text
        set stampText to stampText & (length of pathValue) & ":" & pathValue
    end repeat
    return stampText
end documentStamp

on hintedDocumentIndex(referenceText)
    if referenceText does not start with "cfm-document:" or referenceText does not contain "|" then return 0
    try
        set boundary to my hintSeparator(referenceText)
        set identityText to text 1 thru (boundary - 1) of referenceText
        set hintText to text (boundary + 1) thru -1 of referenceText
        set boundary to my hintSeparator(hintText)
        set hintedIndex to (text 1 thru (boundary - 1) of hintText) as integer
        set expectedStamp to text (boundary + 1) thru -1 of hintText
        if my documentStamp() is expectedStamp then
            tell application id "com.microsoft.Powerpoint" to set p to presentation hintedIndex
            if my matchesDocument(p, identityText) then return hintedIndex
        end if
    end try
    return 0
end hintedDocumentIndex

on findDocument(referenceText)
    tell application id "com.microsoft.Powerpoint"
        -- Validate the full document list and stable ID before using an index.
        -- Save As, opening a copy and closing documents invalidate this hint.
        set hintedIndex to my hintedDocumentIndex(referenceText)
        if hintedIndex > 0 then return presentation hintedIndex
        if referenceText starts with "cfm-document:" and referenceText contains "|" then
            set boundary to my hintSeparator(referenceText)
            set referenceText to text 1 thru (boundary - 1) of referenceText
        end if
        set matches to {}
        if referenceText does not start with "cfm-document:" then
            set paths to get full name of every presentation
            repeat with documentIndex from 1 to (count paths)
                if item documentIndex of paths is referenceText then set end of matches to presentation documentIndex
            end repeat
        else
            repeat with documentIndex from 1 to (count of presentations)
                set p to presentation documentIndex
                if my matchesDocument(p, referenceText) then set end of matches to p
            end repeat
        end if
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

-- Keep one immutable name index for each script operation. PowerPoint does not
-- support a nested `name of every shape of every slide` query, so read once per
-- slide. Resolve types only for matching raw OLE candidates, never every shape.
on figureIndex(p)
    tell application id "com.microsoft.Powerpoint"
        set slideIDs to get slide ID of every slide of p
        set shapeNames to {}
        repeat with slideIndex from 1 to count slideIDs
            set end of shapeNames to get name of every shape of slide slideIndex of p
        end repeat
    end tell
    return {slideIDs, shapeNames}
end figureIndex

on matchingLocations(p, namesIndex, targetText)
    set slideIDs to item 1 of namesIndex
    set shapeNames to item 2 of namesIndex
    set matches to {}
    repeat with slideIndex from 1 to count slideIDs
        set pictureNames to item slideIndex of shapeNames
        set slidePrefix to "ChemOffice OLE Selection:" & (item slideIndex of slideIDs as string) & ":"
        repeat with pictureIndex from 1 to count pictureNames
            set pictureName to item pictureIndex of pictureNames
            set matched to pictureName is targetText
            if targetText does not start with "CFM_OLE_PENDING:" then set matched to matched or my matchesSource(pictureName, targetText)
            if not matched and targetText starts with "ChemOffice OLE Selection:" then
                set rawTag to slidePrefix & pictureName
                set groupTag to slidePrefix & "group:" & pictureName
                if rawTag is targetText or groupTag is targetText then
                    tell application id "com.microsoft.Powerpoint"
                        if shape type of shape pictureIndex of slide slideIndex of p is shape type group then set rawTag to groupTag
                    end tell
                    set matched to rawTag is targetText
                end if
            end if
            if matched then set end of matches to {slideIndex as integer, pictureIndex as integer}
        end repeat
    end repeat
    return matches
end matchingLocations

on run argv
    set actionName to item 1 of argv
    if actionName is "document-status" then
        if application id "com.microsoft.Powerpoint" is not running then return "closed"
    end if
    tell application id "com.microsoft.Powerpoint"
        if actionName is "document-status" then
            set hintedIndex to my hintedDocumentIndex(item 2 of argv)
            if hintedIndex > 0 then return "open" & tab & (hintedIndex as string) & tab & my documentStamp()
            set matchingCount to 0
            repeat with documentIndex from 1 to (count of presentations)
                if my matchesDocument(presentation documentIndex, item 2 of argv) then
                    set matchingCount to matchingCount + 1
                    set matchingIndex to documentIndex as integer
                end if
            end repeat
            if matchingCount is 0 then return "closed"
            if matchingCount is 1 then return "open" & tab & (matchingIndex as string) & tab & my documentStamp()
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
            if (count argv) > 2 then return my contextID(my findDocument(item 3 of argv), item 2 of argv)
            return my contextID(active presentation, item 2 of argv)
        else if actionName is "reference" then
            return full name of active presentation
        else if actionName is "path" then
            set p to my findDocument(item 2 of argv)
            set pathText to full name of p
            if pathText starts with "/" then return pathText
            return ""
        else if actionName is "ole-active" then
            if my matchesDocument(active presentation, item 2 of argv) then return "yes"
            return "no"
        else if actionName is "ole-debug" then
            return (full name of active presentation) & tab & ((count shapes of slide of view of active window) as string)
        else if actionName is "ole-window" then
            set p to my findDocument(item 2 of argv)
            return name of p
        else if actionName is "ole-copy-direct" or actionName is "ole-capture" or actionName is "ole-transport-copy-close" or actionName is "ole-claim" or actionName is "ole-kind" or actionName is "ole-group-export" then
            set p to my findDocument(item 2 of argv)
            set targetText to item 3 of argv
            set namesIndex to my figureIndex(p)
            set matches to my matchingLocations(p, namesIndex, targetText)
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to slide (item 1 of item 1 of matches) of p
            set pic to shape (item 2 of item 1 of matches) of s
            set pictureProperties to properties of pic
            if actionName is "ole-kind" then
                if shape type of pictureProperties is shape type group then return "group"
                if shape type of pictureProperties is shape type embedded OLE control then return "ole"
                return "picture"
            end if
            if actionName is "ole-capture" and shape type of pictureProperties is shape type group then return "group"
            if actionName is "ole-group-export" then
                if shape type of pictureProperties is not shape type group then error "Ambiguous or missing original PowerPoint figure"
                -- Save only a newly created transport containing a copy of the
                -- group. The user's presentation stays open and unsaved.
                copy shape pic
                set sourceWidth to slide width of page setup of p
                set transport to my findDocument(item 4 of argv)
                try
                    set slide width of page setup of transport to sourceWidth
                    set transportSlide to slide 1 of transport
                    paste object view of document window 1 of transport
                    if (count shapes of transportSlide) is not 1 then error "PowerPoint did not insert exactly one OLE object; source retained"
                    save transport
                on error messageText number errorNumber
                    close transport saving no
                    error messageText number errorNumber
                end try
                close transport saving no
                return (slide ID of s as string) & tab & ((count shapes of s) as string) & tab & (left position of pictureProperties as string) & tab & (top of pictureProperties as string) & tab & (width of pictureProperties as string) & tab & (rotation of pictureProperties as string)
            end if
            if actionName is "ole-claim" and shape type of pictureProperties is shape type group then
                set name of pic to item 4 of argv
                return "ok"
            end if
            if actionName is "ole-capture" and shape type of pictureProperties is not shape type embedded OLE control then return "picture"
            if shape type of pictureProperties is not shape type embedded OLE control and not (actionName is "ole-transport-copy-close" and shape type of pictureProperties is shape type group) then error "The selected shape is not an embedded OLE object"
            if actionName is "ole-copy-direct" or actionName is "ole-capture" or actionName is "ole-transport-copy-close" then
                copy shape pic
                if actionName is "ole-transport-copy-close" then
                    close p saving no
                    if my matchesDocument(active presentation, item 4 of argv) then return "ready"
                    return "copied"
                end if
                return (slide ID of s as string) & tab & ((count shapes of s) as string) & tab & (left position of pictureProperties as string) & tab & (top of pictureProperties as string) & tab & (width of pictureProperties as string) & tab & (rotation of pictureProperties as string)
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
            else
                set namesIndex to my figureIndex(p)
                set matches to my matchingLocations(p, namesIndex, figureID)
                if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
                set s to slide (item 1 of item 1 of matches) of p
                set oldPic to shape (item 2 of item 1 of matches) of s
                set pictureLeft to left position of oldPic
                set pictureTop to top of oldPic
                set pictureWidth to width of oldPic
                set pictureRotation to rotation of oldPic
            end if
            if not my matchesDocument(active presentation, item 2 of argv) then error "The target PowerPoint document changed before paste"
            go to slide view of active window number (slide index of s)
            return (slide ID of s as string) & tab & ((count of shapes of s) as string) & tab & (pictureLeft as string) & tab & (pictureTop as string) & tab & (pictureWidth as string) & tab & (pictureRotation as string)
        else if actionName is "ole-transport-close" then
            set p to my findDocument(item 2 of argv)
            close p saving no
            return "closed"
        else if actionName is "ole-paste-direct" or actionName is "ole-stage" or actionName is "ole-paste-stage" or actionName is "ole-group-paste-stage" then
            set p to my findDocument(item 2 of argv)
            set targetID to (item 6 of argv) as integer
            set foundSlides to {}
            set slideIDs to get slide ID of every slide of p
            repeat with slideIndex from 1 to count slideIDs
                if item slideIndex of slideIDs is targetID then set end of foundSlides to slideIndex as integer
            end repeat
            if (count foundSlides) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to slide (item 1 of foundSlides) of p
            set previousCount to (item 7 of argv) as integer
            if actionName is "ole-paste-direct" or actionName is "ole-paste-stage" or actionName is "ole-group-paste-stage" then
                if (count shapes of s) is not previousCount then error "Original image identity changed; retained both versions"
                if not my matchesDocument(active presentation, item 2 of argv) then error "The target PowerPoint document changed before paste"
                go to slide view of active window number (item 1 of foundSlides)
                paste object view of active window
                if actionName is "ole-paste-direct" then return "pasted"
                repeat 80 times
                    if (count shapes of s) is not previousCount then exit repeat
                    delay 0.1
                end repeat
            end if
            if (count shapes of s) is previousCount then return "waiting"
            if (count shapes of s) is not previousCount + 1 then error "PowerPoint did not insert exactly one OLE object; source retained"
            set newPic to shape (previousCount + 1) of s
            set expectedType to shape type embedded OLE control
            if actionName is "ole-group-paste-stage" then set expectedType to shape type group
            if shape type of newPic is not expectedType then
                delete newPic
                error "PowerPoint pasted a picture instead of an OLE object; please retry"
            end if
            set name of newPic to item 12 of argv
            if actionName is "ole-group-paste-stage" then
                set left position of newPic to (item 8 of argv) as real
                set top of newPic to (item 9 of argv) as real
                return "staged"
            end if
            set lock aspect ratio of newPic to false
            set properties of newPic to {left position:(item 8 of argv) as real, top:(item 9 of argv) as real, width:(item 10 of argv) as real, height:((item 10 of argv) as real) * ((item 5 of argv) as real), rotation:(item 11 of argv) as real}
            if actionName is "ole-paste-stage" then copy shape newPic
            return "staged"
        else if actionName is "ole-discard" then
            set p to my findDocument(item 2 of argv)
            if item 3 of argv does not start with "CFM_OLE_PENDING:" then error "Original image identity changed; retained both versions"
            set namesIndex to my figureIndex(p)
            set matches to my matchingLocations(p, namesIndex, item 3 of argv)
            repeat with matchIndex from count matches to 1 by -1
                set location to item matchIndex of matches
                delete shape (item 2 of location) of slide (item 1 of location) of p
            end repeat
            return "discarded"
        else if actionName is "ole-insert-commit" or actionName is "ole-update-commit" then
            set p to my findDocument(item 2 of argv)
            -- Rebuild immediately before mutation: detect a moved/deleted
            -- original or a duplicate marker created while transport imported.
            -- Both identities share this read, including all other slides.
            set namesIndex to my figureIndex(p)
            set newMatches to my matchingLocations(p, namesIndex, item 6 of argv)
            set oldMatches to my matchingLocations(p, namesIndex, item 3 of argv)
            if (count newMatches) is not 1 then error "Cannot uniquely identify the inserted preview; source retained"
            if actionName is "ole-update-commit" then
                if (count oldMatches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
                if (item 1 of item 1 of oldMatches) is not (item 1 of item 1 of newMatches) then error "Original image identity changed; retained both versions"
                set oldShape to shape (item 2 of item 1 of oldMatches) of slide (item 1 of item 1 of oldMatches) of p
                set oldOrder to z order position of oldShape
                set wasGroup to shape type of oldShape is shape type group
                delete oldShape
            end if
            set s to slide (item 1 of item 1 of newMatches) of p
            set name of shape (item 6 of argv) of s to item 4 of argv
            set pictureNames to get name of every shape of s
            repeat with pictureIndex from (count pictureNames) to 1 by -1
                if item pictureIndex of pictureNames is "CFM_OLE_ANCHOR:" & (item 3 of argv) then delete shape pictureIndex of s
            end repeat
            set committedPic to shape (item 4 of argv) of s
            if actionName is "ole-update-commit" and wasGroup then
                repeat while z order position of committedPic > oldOrder
                    z order committedPic z order position send shape backward
                end repeat
            end if
            set committedProperties to properties of committedPic
            return (name of committedProperties) & tab & (width of committedProperties as string) & tab & (height of committedProperties as string)
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
                set pictureNames to get name of every shape of s
                repeat with pictureIndex from 1 to (count pictureNames)
                    if my matchesSource(item pictureIndex of pictureNames, item 3 of argv) then set end of matches to {s, shape pictureIndex of s}
                end repeat
            end repeat
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set s to item 1 of item 1 of matches
            set oldPic to item 2 of item 1 of matches
            set dataBoxes to {}
            set pictureNames to get name of every shape of s
            repeat with pictureIndex from 1 to (count pictureNames)
                if item pictureIndex of pictureNames is dataName then set end of dataBoxes to shape pictureIndex of s
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
            set namesIndex to my figureIndex(p)
            set matches to my matchingLocations(p, namesIndex, item 3 of argv)
            if (count matches) is not 1 then error "Ambiguous or missing original PowerPoint figure"
            set location to item 1 of matches
            set s to slide (item 1 of location) of p
            set index of window (name of p) to 1
            set slide of view of document window 1 of p to s
            select shape (item 2 of location) of s
            activate
            return "activated"
        end if
    end tell
end run
