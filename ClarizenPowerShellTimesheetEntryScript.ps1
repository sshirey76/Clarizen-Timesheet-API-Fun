# Authenticate function
# This function authenticates the user with the Clarizen API and returns an authentication header containing the session ID. 
# It requires valid username and password credentials.

function Authenticate {
    try {
        $auth = @{
            username = $username
            password = $password
        } | ConvertTo-Json

        $baseAPIUri = "https://api2.clarizen.com/v2.0/services"
        $loginURI = "$baseAPIUri/authentication/login"
        $loginResponse = Invoke-RestMethod -Method POST -Uri $loginURI -Body $auth -ContentType "application/json"

        $sessionHeaderContent = $loginResponse
        $authHeader = @{
            "Authorization" = "Session $($sessionHeaderContent.sessionId)"
        }

        return $authHeader
    } catch {
        Write-Error "Error occurred during authentication: $_"
        throw
    }
}

# GetUserInput function
# This function prompts the user for input and validates the input based on the provided minimum and maximum values.
# It supports single or multiple selections and returns the selected value(s) accordingly.
function GetUserInput {
    param (
        [string]$Prompt,
        [int]$Min,
        [int]$Max,
        [switch]$AllowMultiple
    )

    do {
        $input = Read-Host $Prompt
        $selections = $input -split ',' | ForEach-Object { $_.Trim() }

        $isValid = $true
        $selectedValues = @()

        foreach ($selection in $selections) {
            if ([string]::IsNullOrEmpty($selection)) {
                continue
            }

            if ([int]::TryParse($selection, [ref]$null)) {
                $selectedValue = [int]$selection
                if ($selectedValue -ge $Min -and $selectedValue -le $Max) {
                    $selectedValues += $selectedValue
                } else {
                    $isValid = $false
                    Write-Warning "Invalid selection: $selection. Please enter numbers between $Min and $Max."
                    break
                }
            } else {
                $isValid = $false
                Write-Warning "Invalid input: $selection. Please enter valid numbers."
                break
            }
        }
    } while (-not $isValid)

    if ($AllowMultiple) {
        return $selectedValues
    } else {
        return $selectedValues[0]
    }
}

# GetWeekRanges function
# This function generates a list of week ranges based on the number of weeks ahead specified by the user.
# It returns an array of hashtables, each containing the start and end dates of a week range.
function GetWeekRanges {
    param (
        [int]$WeeksAhead
    )

    $weekRanges = @()
    for ($i = 0; $i -le $WeeksAhead; $i++) {
        $startWeek = (Get-Date).AddDays(-(Get-Date).DayOfWeek.value__ + 1 + ($i * 7))
        $endWeek = $startWeek.AddDays(4)
        $weekRanges += @{
            StartDate = $startWeek
            EndDate   = $endWeek
        }
    }

    return $weekRanges
}

# GetSelectedWeekRanges function
# This function prompts the user to select the desired week ranges from the list of available week ranges.
# It allows the user to select multiple week ranges or choose the "All week ranges" option.
# It returns an array of the selected week ranges.
function GetSelectedWeekRanges {
    param (
        [array]$WeekRanges
    )

    Write-Host "Select the week ranges to enter time for:"
    for ($i = 0; $i -lt $WeekRanges.Count; $i++) {
        $startWeekShortDate = $WeekRanges[$i].StartDate.ToString("yyyy-MM-dd")
        $endWeekShortDate = $WeekRanges[$i].EndDate.ToString("yyyy-MM-dd")
        Write-Host "$($i + 1). $startWeekShortDate - $endWeekShortDate"
    }
    Write-Host "$($WeekRanges.Count + 1). All week ranges"

    $selectedWeekRanges = GetUserInput -Prompt "Enter the numbers of your selections (comma-separated) or press Enter to finish selecting" -Min 1 -Max ($WeekRanges.Count + 1) -AllowMultiple

    if ($selectedWeekRanges -contains ($WeekRanges.Count + 1)) {
        return $WeekRanges
    } else {
        return $selectedWeekRanges | ForEach-Object { $WeekRanges[$_ - 1] }
    }
}

# GetActiveTasks function
# This function retrieves the list of active tasks for the specified resource using the Clarizen API.
# It requires the resource identifier and the authentication header.
# It returns an array of active tasks, each containing the task name and ID.
function GetActiveTasks {
    param (
        [string]$Resource,
        [hashtable]$authHeader
    )

    try {
        $select = @"
        SELECT WorkItem.Name, WorkItem.ID
        FROM RegularResourceLink
        WHERE Resource = '$Resource'
        AND WorkItem IN (SELECT ID FROM WorkItem WHERE State = 'Active' and EntityType = 'Task')
        AND State = '/State/Active'
"@
        $body = @{ q = $select }
        $objres = Invoke-RestMethod -Method Get -Uri "https://api2.clarizen.com/V2.0/services/data/query" -Headers $authHeader -Body $body -ContentType "application/json"
        return $objres.entities.WorkItem
    } catch {
        Write-Error "Error occurred while retrieving active tasks: $_"
        throw
    }
}

# GetSelectedTasks function
# This function prompts the user to select the desired tasks from the list of active tasks.
# It allows the user to select multiple tasks and returns the selected task IDs and names.
function GetSelectedTasks {
    param (
        [array]$Tasks
    )

    Write-Host "Press CTRL+C to Cancel OR Please select the Tasks to charge time to:"
    for ($i = 0; $i -lt $Tasks.Count; $i++) {
        Write-Host ("{0} - {1}" -f ($i + 1), $Tasks[$i].Name)
    }

    $selectedTaskNumbers = GetUserInput -Prompt "Enter the numbers of your selections (comma-separated) or press Enter to finish selecting" -Min 1 -Max $Tasks.Count -AllowMultiple

    $selectedTaskIds = $selectedTaskNumbers | ForEach-Object { $Tasks[$_ - 1].ID }
    $selectedTaskNames = $selectedTaskNumbers | ForEach-Object { $Tasks[$_ - 1].Name }

    Write-Host "You Selected These Tasks:"
    $selectedTaskNames | ForEach-Object { Write-Host "- $_" }

    return $selectedTaskIds, $selectedTaskNames
}

# GetTimesheetData function
# This function collects the timesheet data for the selected tasks, week ranges, and days.
# It prompts the user to select the days and enter the number of hours for each selected day or for the whole week.
# It checks if a timesheet already exists for the selected task, date, and resource, and determines whether to create a new timesheet or update an existing one.
# It returns an array of timesheet data containing the action (create or update), task name, reported date, and duration.
function GetTimesheetData {
    param (
        [array]$SelectedTaskIds,
        [array]$SelectedTaskNames,
        [array]$SelectedWeekRanges,
        [string]$Resource,
        [hashtable]$authHeader
    )

    $timesheetData = @()

    foreach ($selectedTaskId in $SelectedTaskIds) {
        $selectedTaskName = $SelectedTaskNames[$SelectedTaskIds.IndexOf($selectedTaskId)]
        $selectedWorkItemId = $selectedTaskId

        foreach ($weekRange in $SelectedWeekRanges) {
            $startWeek = $weekRange.StartDate
            $endWeek = $weekRange.EndDate

            Write-Host "Select the days to apply hours to for task '$selectedTaskName' ($($startWeek.ToString("yyyy-MM-dd")) - $($endWeek.ToString("yyyy-MM-dd"))):"
            Write-Host "1. Monday"
            Write-Host "2. Tuesday"
            Write-Host "3. Wednesday"
            Write-Host "4. Thursday"
            Write-Host "5. Friday"
            Write-Host "6. Whole Week (Monday - Friday)"
            $daysSelection = Read-Host "Enter the numbers of the days (comma-separated) or '6' for the whole week"

            $selectedDays = @()
            if ($daysSelection -eq "6") {
                $selectedDays = 0..4
                $desiredHours = GetUserInput -Prompt "Enter the number of hours to apply each day for the whole week (0-8)" -Min 0 -Max 8
                $desiredHours = "$($desiredHours)h"
            } else {
                $selectedDays = $daysSelection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
            }

            foreach ($day in $selectedDays) {
                $reportedDate = $startWeek.AddDays($day).ToString("yyyy-MM-dd")

                if ($daysSelection -ne "6") {
                    $desiredHours = GetUserInput -Prompt "Enter the number of hours for $($startWeek.AddDays($day).DayOfWeek) ($reportedDate) (0-10)" -Min 0 -Max 8
                    $desiredHours = "$($desiredHours)h"
                }

                try {
                    $query = @"
                    SELECT ReportedDate
                    FROM Timesheet
                    WHERE WorkItem = '$selectedWorkItemId'
                    AND State = '/State/Un Submitted'
                    AND CreatedBy = '$Resource'
                    AND ReportedDate = '$reportedDate'
"@
                    $body = @{ q = $query }
                    $response = Invoke-RestMethod -Uri "https://api2.clarizen.com/V2.0/services/data/query" -Method Get -Headers $authHeader -ContentType "application/json" -Body $body
                } catch {
                    Write-Error "Error occurred while checking existing timesheets: $_"
                    throw
                }

                if ($response.entities -eq $null -or $response.entities.Count -eq 0) {
                    $timesheetData += @{
                        Action       = "Create"
                        WorkItem     = $selectedTaskName
                        ReportedDate = $reportedDate
                        Duration     = $desiredHours
                    }
                } else {
                    $timesheetData += @{
                        Action       = "Update"
                        WorkItem     = $selectedTaskName
                        ReportedDate = $reportedDate
                        Duration     = $desiredHours
                    }
                }
            }
        }
    }

    return $timesheetData
}

# UpdateTimesheets function
# This function updates or creates timesheets based on the collected timesheet data.
# It iterates over each timesheet entry and performs the necessary API calls to create a new timesheet or update an existing one.
function UpdateTimesheets {
    param (
        [array]$TimesheetData,
        [array]$SelectedTaskIds,
        [array]$SelectedTaskNames,
        [string]$Resource,
        [hashtable]$authHeader
    )

    $tsUri = "https://api2.clarizen.com/v2.0/services/data/objects/Timesheet"

    foreach ($timesheet in $TimesheetData) {
        $selectedWorkItemId = $SelectedTaskIds[$SelectedTaskNames.IndexOf($timesheet.WorkItem)]

        if ($timesheet.Action -eq "Create") {
            try {
                $CreateTimesheetBody = @{
                    workitem     = $selectedWorkItemId
                    duration     = $timesheet.Duration
                    reportedDate = $timesheet.ReportedDate
                } | ConvertTo-Json
                $null = Invoke-RestMethod -Uri $tsUri -Method Put -Headers $authHeader -ContentType "application/json" -Body $CreateTimesheetBody
            } catch {
                Write-Error "Error occurred while creating timesheet: $_"
                throw
            }
        } else {
            try {
                $query = @"
                SELECT CreatedOn
                FROM Timesheet
                WHERE WorkItem = '$selectedWorkItemId'
                AND State = '/State/Un Submitted'
                AND CreatedBy = '$Resource'
                AND ReportedDate = '$($timesheet.ReportedDate)'
"@
                $body = @{ q = $query }
                $response = Invoke-RestMethod -Uri "https://api2.clarizen.com/V2.0/services/data/query" -Method Get -Headers $authHeader -ContentType "application/json" -Body $body
                $tsid = $response.entities[0].ID

                $UpdateTimesheetBody = @{
                    ID           = $tsid
                    Duration     = $timesheet.Duration
                    ReportedDate = $timesheet.ReportedDate
                } | ConvertTo-Json
                $null = Invoke-RestMethod -Uri "$tsUri/$tsid" -Method Post -Headers $authHeader -ContentType "application/json" -Body $UpdateTimesheetBody
            } catch {
                Write-Error "Error occurred while updating timesheet: $_"
                throw
            }
        }
    }
}

# Main script
# This is the main entry point of the script. It orchestrates the flow of the script by calling the necessary functions in the correct order.
# It prompts the user for input, retrieves active tasks, collects timesheet data, and updates or creates timesheets based on the user's selections.
try {
    #Enter your Login Credential for Clarizen
    $username = $(Read-Host 'Enter your Clarizen Username for Login.')
    $password = $(Read-Host 'Enter your Clarizen Password for Login.')
    
    # Authenticate and obtain the authentication header
    $authHeader = Authenticate

    # Get the resource identifier for the user to enter time for
    $resource = "/User/$(Read-Host 'Enter the Username you want to enter time for')"

    # Prompt the user to select the number of weeks ahead to enter time for
    $weeksAhead = GetUserInput -Prompt "Enter the number of weeks ahead you want to enter time for (1-4)" -Min 1 -Max 4

    # Generate the week ranges based on the selected number of weeks ahead
    $weekRanges = GetWeekRanges -WeeksAhead $weeksAhead

    # Prompt the user to select the desired week ranges
    $selectedWeekRanges = GetSelectedWeekRanges -WeekRanges $weekRanges

    # Display the selected week ranges
    Write-Host "You have decided to enter time for the following week ranges:"
    foreach ($weekRange in $selectedWeekRanges) {
        Write-Host "- $($weekRange.StartDate.ToString('yyyy-MM-dd')) - $($weekRange.EndDate.ToString('yyyy-MM-dd'))"
    }

    # Retrieve the list of active tasks for the specified resource
    $tasks = GetActiveTasks -Resource $resource -AuthHeader $authHeader

    # Prompt the user to select the desired tasks
    $selectedTaskIds, $selectedTaskNames = GetSelectedTasks -Tasks $tasks

    # Collect timesheet data for the selected tasks, week ranges, and days
    $timesheetData = GetTimesheetData -SelectedTaskIds $selectedTaskIds -SelectedTaskNames $selectedTaskNames -SelectedWeekRanges $selectedWeekRanges -Resource $resource -AuthHeader $authHeader

    # Display a summary of the timesheets to be updated or created
    Write-Host "Summary of timesheets to be updated or created:"
    $timesheetData | Format-Table -AutoSize

    # Prompt the user for confirmation before proceeding with the updates
    $confirmation = Read-Host "Do you want to proceed with updating/creating the timesheets? (Y/N)"

    if ($confirmation -eq "Y" -or $confirmation -eq "y") {
        # If the user confirms, proceed with updating or creating the timesheets
        UpdateTimesheets -TimesheetData $timesheetData -SelectedTaskIds $selectedTaskIds -SelectedTaskNames $selectedTaskNames -Resource $resource -AuthHeader $authHeader
        Write-Host "Timesheets updated/created successfully."
    } else {
        # If the user cancels, display a message indicating that no changes were made
        Write-Host "Operation cancelled. No timesheets were updated or created."
    }
} catch {
    # If an error occurs during the execution of the script, display an error message
    Write-Error "An error occurred: $_"
}