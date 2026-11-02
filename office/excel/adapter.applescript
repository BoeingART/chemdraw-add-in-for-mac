-- SPDX-License-Identifier: Apache-2.0
on matchesSource(tagText, drawingID)
    return tagText is "ChemOffice Drawing:" & drawingID or tagText starts with "ChemOffice Drawing:" & drawingID & ":" or tagText starts with "CFM1:" & drawingID & ":" or tagText starts with "CFM2:" & drawingID & ":"
end matchesSource

on existingID(book)
    tell application id "com.microsoft.Excel"
        repeat with propertyIndex from 1 to (count of named items of book)
            set p to named item propertyIndex of book
            if name of p is "_ChemOfficeDocumentID" then
                set encodedID to value of p
                if encodedID does not start with "=\"" or encodedID does not end with "\"" or (length of encodedID) is not 39 then error "The original Excel workbook is no longer uniquely available"
                return text 3 thru -2 of encodedID
            end if
        end repeat
        return ""
    end tell
end existingID

on documentPath(book)
    tell application id "com.microsoft.Excel"
        if path of book is "" then return ""
        set locationText to full name of book
        if locationText starts with "/" then return locationText
        return POSIX path of (locationText as alias)
    end tell
end documentPath

on matchesDocument(book, referenceText)
    if referenceText starts with "cfm-document:" then return "cfm-document:" & my existingID(book) is referenceText
    tell application id "com.microsoft.Excel" to return my documentPath(book) is referenceText or name of book is referenceText
end matchesDocument

on findDocument(referenceText)
    tell application id "com.microsoft.Excel"
        set matches to {}
        repeat with bookIndex from 1 to (count of workbooks)
            set book to workbook bookIndex
            if my matchesDocument(book, referenceText) then set end of matches to book
        end repeat
        if (count matches) is not 1 then error "The original Excel workbook is no longer uniquely available"
        return item 1 of matches
    end tell
end findDocument

on contextID(book, candidateID)
    tell application id "com.microsoft.Excel"
        set identityText to my existingID(book)
        if identityText is not "" then
            set matches to 0
            repeat with bookIndex from 1 to (count of workbooks)
                if my existingID(workbook bookIndex) is identityText then set matches to matches + 1
            end repeat
            if matches > 1 then error "Close the other copy of this Excel workbook before editing its drawing"
        else
            make new named item at book with properties {name:"_ChemOfficeDocumentID", references:"=\"" & candidateID & "\"", visible:false}
        end if
        if identityText is "" then set identityText to candidateID
        return "cfm-document:" & identityText
    end tell
end contextID

on findFigure(book, drawingID)
    tell application id "com.microsoft.Excel"
        set matches to {}
        repeat with sheetIndex from 1 to (count of worksheets of book)
            set s to worksheet sheetIndex of book
            repeat with shapeIndex from 1 to (count of shapes of s)
                set pic to shape shapeIndex of s
                if name of pic is drawingID or my matchesSource(name of pic, drawingID) or "ChemOffice OLE Selection:" & name of s & ":" & name of pic is drawingID then set end of matches to {s, pic}
            end repeat
        end repeat
        if (count matches) is not 1 then error "Ambiguous or missing original Excel figure"
        return item 1 of matches
    end tell
end findFigure

on run argv
    set actionName to item 1 of argv
    set separatorText to character id 9
    if actionName is "document-status" then
        if application id "com.microsoft.Excel" is not running then return "closed"
    end if
    tell application id "com.microsoft.Excel"
        if actionName is "document-status" then
            set matchingCount to 0
            repeat with bookIndex from 1 to (count of workbooks)
                if my matchesDocument(workbook bookIndex, item 2 of argv) then set matchingCount to matchingCount + 1
            end repeat
            if matchingCount is 0 then return "closed"
            if matchingCount is 1 then return "open"
            return "ambiguous"
        else if actionName is "context" then
            if (count argv) > 2 then return my contextID(my findDocument(item 3 of argv), item 2 of argv)
            return my contextID(active workbook, item 2 of argv)
        else if actionName is "reference" then
            set pathText to my documentPath(active workbook)
            if pathText is not "" then return pathText
            return name of active workbook
        else if actionName is "ole-kind" or actionName is "ole-capture" or actionName is "ole-claim" or actionName is "ole-transport-copy-close" then
            set book to my findDocument(item 2 of argv)
            set targetFigure to my findFigure(book, item 3 of argv)
            set pic to item 2 of targetFigure
            if actionName is "ole-claim" then
                set name of pic to item 4 of argv
                return "claimed"
            end if
            if shape type of pic is not shape type embedded OLE control then return "picture"
            if actionName is "ole-kind" then return "ole"
            copy object pic
            if actionName is "ole-transport-copy-close" then close book saving no
            return "copied"
        else if actionName is "ole-transport-close" then
            close (my findDocument(item 2 of argv)) saving no
            return "closed"
        else if actionName is "ole-insert-prepare" or actionName is "ole-update-prepare" then
            set book to my findDocument(item 2 of argv)
            set originalMarker to "-"
            if actionName is "ole-insert-prepare" then
                if not my matchesDocument(active workbook, item 2 of argv) then error "The target Excel workbook changed before paste"
                set s to active sheet of book
                if worksheet type of s is not sheet type worksheet then error "Select a worksheet cell before pasting a drawing"
                set x to left position of active cell
                set y to top of active cell
                set w to 240
                set angle to 0
            else
                set targetFigure to my findFigure(book, item 3 of argv)
                set s to item 1 of targetFigure
                set pic to item 2 of targetFigure
                set originalMarker to name of pic
                set x to left position of pic
                set y to top of pic
                set w to width of pic
                set angle to rotation of pic
            end if
            return (name of s) & separatorText & ((count shapes of s) as string) & separatorText & (x as string) & separatorText & (y as string) & separatorText & (w as string) & separatorText & (angle as string) & separatorText & originalMarker
        else if actionName is "ole-paste-stage" then
            set book to my findDocument(item 2 of argv)
            set s to worksheet (item 6 of argv) of book
            set originalCount to (item 7 of argv) as integer
            if (count shapes of s) is not originalCount then error "Original Excel figure changed during write-back; retained both versions"
            activate object book
            activate object s
            if not my matchesDocument(active workbook, item 2 of argv) then error "The target Excel workbook changed before paste"
            paste worksheet s
            if (count shapes of s) is not originalCount + 1 then error "Excel replacement could not be verified; draft retained"
            set pic to shape (originalCount + 1) of s
            set name of pic to item 13 of argv
            if shape type of pic is not shape type embedded OLE control then error "Excel pasted a picture instead of an OLE object"
            set lock aspect ratio of pic to false
            set left position of pic to (item 8 of argv) as real
            set top of pic to (item 9 of argv) as real
            set width of pic to (item 10 of argv) as real
            set height of pic to ((item 10 of argv) as real) * ((item 5 of argv) as real)
            set rotation of pic to (item 11 of argv) as real
            if item 12 of argv is "-" then
                set placement of pic to placement move and size
            else
                set targetFigure to my findFigure(book, item 3 of argv)
                set oldPic to item 2 of targetFigure
                set placement of pic to placement of oldPic
                set lock aspect ratio of pic to lock aspect ratio of oldPic
            end if
            copy object pic
            return "staged"
        else if actionName is "ole-insert-commit" or actionName is "ole-update-commit" then
            set book to my findDocument(item 2 of argv)
            set newFigure to my findFigure(book, item 6 of argv)
            if actionName is "ole-update-commit" then
                set oldFigure to my findFigure(book, item 3 of argv)
                if name of item 2 of oldFigure is not item 7 of argv then error "Original Excel figure changed during write-back; retained both versions"
                if name of item 1 of oldFigure is not name of item 1 of newFigure then error "Original Excel figure changed during write-back; retained both versions"
                set oldPic to item 2 of oldFigure
                delete oldPic
            end if
            set newFigure to my findFigure(book, item 6 of argv)
            set pic to item 2 of newFigure
            set name of pic to item 4 of argv
            return (name of pic) & separatorText & (width of pic as string) & separatorText & (height of pic as string)
        else if actionName is "ole-discard" then
            set book to my findDocument(item 2 of argv)
            if item 3 of argv does not start with "CFM_OLE_PENDING:" then error "Original Excel figure changed during write-back; retained both versions"
            repeat with sheetIndex from 1 to count worksheets of book
                set s to worksheet sheetIndex of book
                repeat with shapeIndex from count shapes of s to 1 by -1
                    if name of shape shapeIndex of s is item 3 of argv then delete shape shapeIndex of s
                end repeat
            end repeat
            return "discarded"
        else if actionName is "path" then
            return my documentPath(my findDocument(item 2 of argv))
        else if actionName is "selected" then
            try
                set selectedObject to get selection
                set selectedName to name of selectedObject
                return selectedName
            on error
                return ""
            end try
        else if actionName is "insert" or actionName is "demo" then
            if (count of argv) < 6 then error "Drawing proportions are missing; no figure inserted"
            if actionName is "demo" then
                set book to make new workbook
                set drawingID to item 5 of argv
            else
                set book to my findDocument(item 5 of argv)
                if not my matchesDocument(active workbook, item 5 of argv) then error "The target Excel workbook changed before paste"
            end if
            set s to active sheet of book
            if worksheet type of s is not sheet type worksheet then error "Select a worksheet cell before pasting a drawing"
            set x to left position of active cell
            set y to top of active cell
            set pic to make new picture at s with properties {file name:item 2 of argv, link to file:false, save with document:true}
            set pic to shape (name of pic) of s
            set lock aspect ratio of pic to false
            set left position of pic to x
            set top of pic to y
            set width of pic to 240
            set height of pic to 240 * ((item 6 of argv) as real)
            set placement of pic to placement move and size
            if actionName is "demo" then
                set name of pic to "ChemOffice Drawing:" & drawingID
                save workbook as book filename (item 4 of argv) file format Excel XML file format
                return item 4 of argv
            end if
            set name of pic to item 3 of argv
            select pic
            return "inserted"
        else if actionName is "payload" or actionName is "inspect" or actionName is "update" or actionName is "activate" then
            set book to my findDocument(item 2 of argv)
            set targetFigure to my findFigure(book, item 3 of argv)
            set s to item 1 of targetFigure
            set oldPic to item 2 of targetFigure
            if actionName is "payload" then return name of oldPic
            if actionName is "inspect" then return (name of oldPic as string) & separatorText & (width of oldPic as string) & separatorText & (height of oldPic as string)
            if actionName is "activate" then
                activate object book
                activate object s
                select oldPic
                activate
                return "activated"
            end if
            set oldName to name of oldPic
            if oldName is item 5 of argv then return "updated"
            set oldTag to name of oldPic
            set x to left position of oldPic
            set y to top of oldPic
            set w to width of oldPic
            set h to height of oldPic
            set originalPlacement to placement of oldPic
            set originalRotation to rotation of oldPic
            set originalLock to lock aspect ratio of oldPic
            if (count of argv) >= 6 then set h to w * ((item 6 of argv) as real)
            set replacementName to "ChemOffice_" & (item 3 of argv) & "_" & (random number from 100000000 to 999999999)
            set newPic to make new picture at s with properties {file name:item 4 of argv, link to file:false, save with document:true}
            set newPic to shape (name of newPic) of s
            set name of newPic to replacementName
            set lock aspect ratio of newPic to false
            set left position of newPic to x
            set top of newPic to y
            set width of newPic to w
            set height of newPic to h
            set placement of newPic to originalPlacement
            set rotation of newPic to originalRotation
            set lock aspect ratio of newPic to originalLock
            set name of newPic to item 5 of argv
            if name of shape oldName of s is not oldTag then error "Original Excel figure changed during write-back; retained both versions"
            delete shape oldName of s
            if name of shape (item 5 of argv) of s is not item 5 of argv then error "Excel replacement could not be verified; draft retained"
            return "updated"
        end if
    end tell
end run
