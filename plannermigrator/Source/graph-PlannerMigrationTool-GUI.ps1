##Author: Sean McAvinue
##Details: Used as a Graph/PowerShell example, 
##          NOT FOR PRODUCTION USE! USE AT YOUR OWN RISK
##          Exports Planner instances to CSV files
function GetDelegatedGraphToken {

    <#
    .SYNOPSIS
    Azure AD OAuth Application Token for Graph API
    Get OAuth token for a AAD Application using delegated permissions via the MSAL.PS library(returned as $token)

    .PARAMETER clientID
    -is the app clientID

    .PARAMETER tenantID
    -is the directory ID of the tenancy

    .PARAMETER redirectURI
    -is the redirectURI specified in the application registration, default value is https://localhost

    #>

    # Application (client) ID, tenant ID and secret
    Param(
        [parameter(Mandatory = $true)]
        [String]
        $clientID,
        [parameter(Mandatory = $true)]
        [String]
        $tenantID,
        [parameter(Mandatory = $false)]
        $RedirectURI = "https://localhost"
    )

    $Token = Get-MsalToken -DeviceCode -ClientId $clientID -TenantId $tenantID -RedirectUri $RedirectURI

    return $token
}


function RunQueryandEnumerateResults {
    <#
    .SYNOPSIS
    Runs Graph Query and if there are any additional pages, parses them and appends to a single variable
    
    .PARAMETER apiUri
    -APIURi is the apiUri to be passed
    
    .PARAMETER token
    -token is the auth token
    
    #>
    Param(
        [parameter(Mandatory = $true)]
        [String]
        $apiUri,
        [parameter(Mandatory = $true)]
        $token

    )

    #Run Graph Query
    write-host running $apiuri -foregroundcolor blue

    $Results = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token)" } -Uri $apiUri -Method Get)

    #Output Results for debug checking
    #write-host $results

    #Begin populating results
    $ResultsValue = $Results.value

    #If there is a next page, query the next page until there are no more pages and append results to existing set
    if ($results."@odata.nextLink" -ne $null) {
        write-host enumerating pages -ForegroundColor yellow
        $NextPageUri = $results."@odata.nextLink"
        ##While there is a next page, query it and loop, append results
        While ($NextPageUri -ne $null) {
            $NextPageRequest = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token)" } -Uri $NextPageURI -Method Get)
            $NxtPageData = $NextPageRequest.Value
            $NextPageUri = $NextPageRequest."@odata.nextLink"
            $ResultsValue = $ResultsValue + $NxtPageData
        }
    }

    ##Return completed results
    return $ResultsValue

    
}

function ListGroups {
    <#
    .SYNOPSIS
    Runs Graph Query to list groups in the tenant
    
    .PARAMETER token
    -token is the auth token
    
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $false)]
        $SearchTerm
    )
    ##Gets Unified Groups

    if ($SearchTerm) {
        $apiUri = "https://graph.microsoft.com/v1.0/groups/?`$filter=groupTypes/any(c:c+eq+'Unified') and startsWith(mail,'$SearchTerm')"
        write-host $apiuri
        $Grouplist = RunQueryandEnumerateResults -token $token.accesstoken -apiUri $apiUri   
    }
    else {
    
        $apiUri = "https://graph.microsoft.com/beta/groups/?`$filter=groupTypes/any(c:c+eq+'Unified')"
        $Grouplist = RunQueryandEnumerateResults -token $token.accesstoken -apiUri $apiUri
    }
    Write-host Found $grouplist.count Groups to process -foregroundcolor yellow

    Return $Grouplist

}

function ListPlans {
    <#
    .SYNOPSIS
    Runs Graph Query to list groups in the tenant
    
    .PARAMETER token
    -token is the auth token

    .PARAMETER GroupID
    -the GroupID of the group continaing the plan
    
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $false)]
        $GroupID
    )

    $apiUri = "https://graph.microsoft.com/beta/groups/$($Groupid)/planner/plans"
    $Plans = RunQueryandEnumerateResults -apiUri $apiUri -token $token.accesstoken

    Return $plans

}


function exportplanner {
    <#
    .SYNOPSIS
    This function gets Graph Token from the GetGraphToken Function and uses it to request a new guest user

    .PARAMETER token
    -is the source auth token
    
    .PARAMETER PlanID
    -is the Plan ID of the source Plan
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $PlanID 
    )
    


    $apiUri = "https://graph.microsoft.com/beta/planner/plans/$($planid)/details"
    $PlanDetails = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -Uri $apiUri -Method Get)
  
    $PlanDetailsExport = [PSCustomObject]@{
        categoryDescriptions = $PlanDetails.categoryDescriptions
    }            

   
    $PlanDetailsExport  | ConvertTo-Json |  out-file "c:\plannermigrator\exportdirectory\$($planid)-planDetails.json" -NoClobber -Append

    $apiUri = "https://graph.microsoft.com/beta/planner/plans/$($planid)/buckets"
    $buckets = RunQueryandEnumerateResults -apiUri $apiUri -token $token.accesstoken
    if ($buckets) {
        $buckets | ConvertTo-Json |  out-file "c:\plannermigrator\exportdirectory\$($planid)-buckets.json" -NoClobber -Append
    }
            
        
    
    $apiUri = "https://graph.microsoft.com/beta/planner/plans/$($planid)/tasks"
    
    $tasks = RunQueryandEnumerateResults -apiUri $apiUri -token $token.accesstoken
    if ($tasks) {
        $tasks  | ConvertTo-Json |  out-file "c:\plannermigrator\exportdirectory\$($planid)-tasks.json" -NoClobber -Append

        foreach ($task in $tasks) {

            $apiUri = "https://graph.microsoft.com/beta/planner/tasks/$($task.id)/details"
            $taskdetails = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -Uri $apiUri -Method Get)
            $taskdetails  | ConvertTo-Json |  out-file "c:\plannermigrator\exportdirectory\$($task.id)-taskdetails.json" -NoClobber -Append
            start-sleep 1
        }
            
                   
            
        

    }
    

}



function CreatePlan {
    <#
    .SYNOPSIS
    Provisions a Plan in the created group. Returns the Plan object
    
    .PARAMETER token
    -token is the auth token
    
    .PARAMETER token
    -the Group ID of the Group created for the planner instance
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $GroupID,
        [parameter(Mandatory = $true)]
        $Title
    )
    $RequestBody = @"

    {
        'owner': '$($groupid)',
        'title': '$($title)'
      }
"@
    

    write-host $RequestBody
      
    $apiUri = "https://graph.microsoft.com/beta/planner/plans"
    ##Invoke Group Request
    $Plan = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -ContentType 'application/json' -Body $RequestBody -Uri $apiUri -Method Post)

    $plandetailsfile = Get-ChildItem C:\plannermigrator\exportdirectory\ | ? { $_.name -like "*-planDetails.json" }
    $PlanDetailsBody = get-content "C:\plannermigrator\exportdirectory\$($plandetailsfile.name)"
    write-host "Assigning Categories $plandetailsbody"
    start-sleep 5
    $apiUri = "https://graph.microsoft.com/beta/planner/plans/$($plan.id)/details"
    $existing = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -Uri $apiUri -Method Get
    Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)"; 'If-Match' = $existing.'@odata.etag' } -ContentType 'application/json' -Body $PlanDetailsBody -Uri $apiUri -Method Patch


    return $Plan

}

function CreateBuckets {
    <#
    .SYNOPSIS
    Provisions Buckets for each control category. 
    
    .PARAMETER token
    -token is the auth token
    
    .PARAMETER buckets
    -the buckets to provision

    .PARAMETER plan
    -the plan to create the buckets in
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $buckets,
        [parameter(Mandatory = $true)]
        $Plan

    )

    $NewBuckets = @()
    foreach ($bucket in $buckets) {
        $RequestBody = @"

    {
        'name': '$($bucket.name)',
        'planId': '$($plan.id)',
        'orderHint': '$(" !")'
      }
"@
        write-host $RequestBody -Verbose
        $apiUri = "https://graph.microsoft.com/beta/planner/buckets"
        ##Invoke Group Request
        $Bucket = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -ContentType 'application/json' -Body $RequestBody -Uri $apiUri -Method Post)
        $Newbuckets += $bucket
    }

    return $NewBuckets
}

function CreateTasks {
    <#
    .SYNOPSIS
    Provisions tasks for each item in the relevent Buckets. 
    
    .PARAMETER token
    -token is the auth token

    .PARAMETER taskBody
    -the task object
        
    .PARAMETER taskDetailsBody
    -the task details object
    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $TaskBody,
        [parameter(Mandatory = $true)]
        $TaskDetailsBody
    )


 
    $apiUri = "https://graph.microsoft.com/v1.0/planner/tasks"
    ##Create Task
    write-host "Provisioning Task $taskbody END" -ForegroundColor green
    $TaskBody
    $task = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)" } -ContentType 'application/json' -Body $TaskBody -Uri $apiUri -Method Post) 

    start-sleep 5

    $apiUri = "https://graph.microsoft.com/v1.0/planner/tasks/$($task.id)/details"
    write-host "getting created task Details"
    $taskdetails = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.accesstoken)" } -Uri $ApiUri -Method Get)
    write-host "Provisioning Task Details $taskdetailsbody" -ForegroundColor yellow
    write-host $apiUri -ForegroundColor blue
    #pause
    Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)"; 'If-Match' = $taskdetails.'@odata.etag' } -ContentType 'application/json' -Body $TaskDetailsBody -Uri $apiUri -Method Patch

    return $task
}



function importplanner {
    <#
    .SYNOPSIS
    This function gets Graph Token from the GetGraphToken Function and uses it to request a new guest user

    .PARAMETER token
    -is the destination auth token

    .PARAMETER PlanID
    -is the dId of the plan in the source
    
    .PARAMETER TargetGroupID
    -is the destination group ID
    
    .PARAMETER PlanName
    -is the name of the plan


    #>
    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $TargetGroupID,
        [parameter(Mandatory = $true)]
        $PlanID,
        [parameter(Mandatory = $true)]
        $PlanName
    )
    

    $Bucketfile = Get-Content "C:\plannermigrator\exportdirectory\$($Planid)-buckets.json"
    $Taskfile = Get-Content "C:\plannermigrator\exportdirectory\$($Planid)-tasks.json"

    $Taskfile
    $Bucketfile

    $NewPlan = CreatePlan -token $token -GroupID $TargetGroupID -Title $PlanName

    
    $buckets = $Bucketfile | ConvertFrom-Json 

    $NewBuckets = CreateBuckets -token $token -buckets $buckets -Plan $NewPlan


    $tasks = $Taskfile | ConvertFrom-Json


    foreach ($task in $tasks) {

        $OldTaskBucket = $buckets | ? { $_.id -like $task.bucketid }

        $NewTaskBucket = $NewBuckets | ? { $_.name -like $OldTaskBucket.name }
        if (!($task.dueDateTime)) {
            $TaskBody = @"
            {
                "planId": '$($NewTaskBucket.planid)',
                "bucketId": '$($NewTaskBucket.id)',
                "title": '$($task.title)',
                "percentComplete": '$($task.percentComplete)'
    
              }
"@
    
        }
    
        else {
            $TaskBody = @"
        {
            "planId": '$($NewTaskBucket.planid)',
            "bucketId": '$($NewTaskBucket.id)',
            "title": '$($task.title)',
            "percentComplete": '$($task.percentComplete)',
            "dueDateTime":  '$($task.dueDateTime)'

          }
"@

        }

        $TaskDetailsFile = Get-Content "C:\plannermigrator\exportdirectory\$($Task.id)-taskdetails.json"
        $TaskDetails = $TaskDetailsFile | ConvertFrom-Json 

        $checklists = Get-Member -InputObject $taskdetails.checklist | ? { $_.membertype -like "NoteProperty" }
        foreach ($checklist in $checklists) {
            $taskdetails.checklist.($checklist.name).orderHint = " !"
            $taskdetails.checklist.($checklist.name).lastModifiedBy = ""
            $taskdetails.checklist.($checklist.name).lastModifiedDateTime = ""
        }
        $TaskDetails.id = ""
        $TaskDetails.'@odata.context' = ""
        $TaskDetails.'@odata.etag' = ""
        $TaskDetails.references = ""

        $TaskDetailsBody = $TaskDetails | ConvertTo-Json
        $TaskDetailsBody = $taskdetailsbody.replace('"lastModifiedDateTime":  "",', '')
        $TaskDetailsBody = $taskdetailsbody.replace('"lastModifiedby":  "",', '')
        $TaskDetailsBody = $taskdetailsbody.replace('"lastModifiedBy":  ""', '')
        $TaskDetailsBody = $taskdetailsbody.replace('"lastModifiedby":  "@{user=}"', '')
        $TaskDetailsBody = $taskdetailsbody.replace('"references":  "",', '')
        $TaskDetailsBody = $taskdetailsbody.replace('"orderHint":  " !",', '"orderHint":  " !"')

        $newTask = CreateTasks -token $token -TaskBody $TaskBody -TaskDetailsBody $TaskDetailsBody

        foreach ($category in $task.appliedCategories) {

 
            $CategoryBody = [PSCustomObject]@{
                appliedCategories = $category
            }
            
            $JSONBody = $CategoryBody | ConvertTo-Json
            $jsonbody
            write-host "Updating $newTask" -ForegroundColor green
            $apiUri = "https://graph.microsoft.com/beta/planner/tasks/$($newTask.id)"
            Invoke-RestMethod -Headers @{Authorization = "Bearer $($token.accesstoken)"; 'If-Match' = $newTask.'@odata.etag' } -ContentType 'application/json' -Body $JSONBody -Uri $apiUri -Method Patch

        }

        if ($global:UserMapping) {
            write-host "User mapping enabled, continuing.."
            translateUsers -oldtask $task -newtask $newTask -token $token


        }
    }
    



}

function translateUsers {
    <#
    .SYNOPSIS
    This function maps user assignments to recently created tasks

    .PARAMETER token
    -is the destination auth token

    .PARAMETER newtask
    -is the newly created task

    .PARAMETER oldtask
    -is the source task
    #>

    Param(
        [parameter(Mandatory = $true)]
        $token,
        [parameter(Mandatory = $true)]
        $newtask,
        [parameter(Mandatory = $true)]
        $oldtask

    )

    try {

        write-host "Processing user mapping for $newtask"
        
        $MappingFile = import-csv C:\plannermigrator\UserMapping\UserMappingFile.csv

        $users = (get-member -InputObject $task.assignments -MemberType noteproperty).name
        write-host $users

        foreach ($olduser in $users) {
            $user = $MappingFile | ? { $_.SourceObjectId -eq $olduser }
            if ($user) {
                write-host "-----------------------------------------------------------------------" -ForegroundColor green
                write-host $user.targetupn being added to $newtask.id
                write-host "-----------------------------------------------------------------------" -ForegroundColor Yellow

                $assignmentbody = @"

{
    "assignments": {
        "$($user.TargetObjectID)": {
            "@odata.type": "#microsoft.graph.plannerAssignment",
            "orderHint": " !"
        }
    }
}
"@
            
                write-host "Updating $($newtask.title)" -ForegroundColor green
                $apiUri = "https://graph.microsoft.com/v1.0/planner/tasks/$($newtask.id)"
                Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.AccessToken)"; 'If-Match' = $newtask.'@odata.etag' } -ContentType 'application/json' -Body $assignmentbody -Uri $apiUri -Method Patch
            }
        }
    }
    catch {
        write-host "Error processing user mapping file, file may be locked or missing!"
    }
        
    

}

Add-Type -AssemblyName PresentationFramework
$global:SourceToken = $null
$global:DestToken = $null
$global:UserMapping = $False
$xamlFile = "MainWindow.xaml"
$inputXML = Get-Content $xamlFile -Raw
$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
[XML]$XAML = $inputXML

#Read XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try {
    $window = [Windows.Markup.XamlReader]::Load( $reader )
}
catch {
    Write-Warning $_.Exception
    throw
}

# Create variables based on form control names.
# Variable will be named as 'var_<control name>'

$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    #"trying item $($_.Name)"
    try {
        Set-Variable -Name "var_$($_.Name)" -Value $window.FindName($_.Name) -ErrorAction Stop
    }
    catch {
        throw
    }
}
Get-Variable var_*

##Connect button for source environment
$var_ConnectButton_Src.Add_Click( {

        try {
            $global:SourceToken = GetDelegatedGraphToken -tenantID $var_TenantIDEntry_Src.text -clientID $var_AppIDEntry_Src.text
            $var_ConnectedLabel_src.content = "Connected Successfully!"
            $var_GroupSearchInput_Src.isEnabled = "true"
            $var_SearchGroupsButton_Src.isEnabled = "true"
            $var_GroupList_Src.isEnabled = "true"
            $var_SelectGroupButton_Src.isEnabled = "true"
            $var_PlanList_Src.isEnabled = "true"
            $var_SelectPlanButton_Src.isEnabled = "true"
            $var_IncludeUserMappingsCheckbox.isEnabled = "true"
        }
        catch {
            $var_ConnectedLabel_src.content = "Connection failed!"
            write-host $_.Exception.Message
        }
    })

##Connect button for destination environment
$var_ConnectButton_Dest.Add_Click( {

        try {
            $global:DestToken = GetDelegatedGraphToken -tenantID $var_TenantIDEntry_dest.text -clientID $var_AppIDEntry_dest.text
            $var_ConnectedLabel_dest.content = "Connected Successfully!"
            $var_GroupSearchInput_Dst.isEnabled = "true"
            $var_SearchGroupsButton_Dst.isEnabled = "true"
            $var_GroupList_Dst.isEnabled = "true"
            $var_SelectGroupButton_Dst.isEnabled = "true"
        }
        catch {
            $var_ConnectedLabel_dest.content = "Connection failed!"
            write-host $_.Exception.Message
        }
    })

##Search button to list groups
$var_SearchGroupsButton_Src.Add_Click( {

        $var_GroupList_Src.Items.Clear()
        write-host "Searching for Groups, please wait"
        $Grouplist = ListGroups -token $SourceToken -searchterm $var_GroupSearchInput_Src.text
        write-host $grouplist.mail
        foreach ($Group in $Grouplist) {
            $var_GroupList_Src.Items.Add($Group.mail) | Out-Null
        
        }
        $var_GroupList_Src.Visibility = "Visible"
        $var_SelectGroupButton_Src.Visibility = "Visible"
    
    })

##Select Group button to list plans
$var_SelectGroupButton_Src.Add_Click( {
        $var_PlanList_Src.Items.Clear()
        write-host "Selected $($var_GroupList_Src.selectedvalue)"
        $global:SourceGroup = ListGroups -token $SourceToken -searchterm $var_GroupList_Src.selectedvalue
        write-host "ID is: $($sourcegroup.id)"
        $Plans = ListPlans -token $SourceToken -GroupId $SourceGroup.ID
        $var_SourceGroupIDLabel_Src.content = $SourceGroup.ID
        foreach ($Plan in $Plans) {
            $PlanEntry = ("$($plan.title);$($Plan.id)")
            $var_PlanList_Src.Items.Add($PlanEntry) | Out-Null
        }
    })

##Select Plan button to choose source plan to migrate
$var_SelectPlanButton_Src.Add_Click( {

        $var_SourcePlanNameLabel_Src.Content = $var_PlanList_Src.selectedvalue.split(';')[0]
        $var_SourcePlanIDLabel_Src.Content = $var_PlanList_Src.selectedvalue.split(';')[1]
        if ($var_DestGroupIDLabel_Dst.content) {
            $var_MigrateButton.isenabled = "true"
        }
    })

##Search button to list Destination groups
$var_SearchGroupsButton_Dst.Add_Click( {

        $var_GroupList_Dst.Items.Clear()
        write-host "Searching for Groups, please wait"
        $Grouplist = ListGroups -token $DestToken -searchterm $var_GroupSearchInput_Dst.text
        write-host $grouplist.mail
        foreach ($Group in $Grouplist) {
            $var_GroupList_Dst.Items.Add($Group.mail) | Out-Null
        
        }
        $var_GroupList_Dst.Visibility = "Visible"
        $var_SelectGroupButton_Dst.Visibility = "Visible"
    
    })

##Select Destination Group Button
$var_SelectGroupButton_Dst.Add_Click( {

        write-host "Selected $($var_GroupList_Dst.selectedvalue)"
        $global:DestGroup = ListGroups -token $DestToken -searchterm $var_GroupList_Dst.selectedvalue
        write-host "ID is: $($Destgroup.id)"
        $var_DestGroupIDLabel_Dst.content = $DestGroup.ID
        if ($var_SourcePlanIDLabel_Src.Content) {
            $var_MigrateButton.isenabled = "true"
        }
    })

##Select MigrateButton Button
$var_MigrateButton.Add_Click( {
        $var_GroupSearchInput_Src.isEnabled = "false"
        $var_SearchGroupsButton_Src.isEnabled = "false"
        $var_GroupList_Src.isEnabled = "false"
        $var_SelectGroupButton_Src.isEnabled = "false"
        $var_PlanList_Src.isEnabled = "false"
        $var_SelectPlanButton_Src.isEnabled = "false"
        $var_GroupSearchInput_Src.isEnabled = "false"
        $var_SearchGroupsButton_Src.isEnabled = "false"
        $var_GroupList_Src.isEnabled = "false"
        $var_SelectGroupButton_Src.isEnabled = "false"
        $var_PlanList_Src.isEnabled = "false"
        $var_SelectPlanButton_Src.isEnabled = "false"
        $var_MigrationStatusLabel.content = "Starting Export..." 
        $var_MigrateProgress.value = 10  
        New-Item -Path c:\plannermigrator\exportdirectory\ -ItemType directory -Force
        exportplanner -token $SourceToken -PlanID $var_SourcePlanIDLabel_Src.content
        $var_MigrationStatusLabel.content = "Export Complete, starting import..." 
        $var_MigrateProgress.value = 50  
        importplanner -token $DestToken -TargetGroupID $var_DestGroupIDLabel_Dst.content -planid $var_SourcePlanIDLabel_Src.content -planname $var_SourcePlanNameLabel_Src.content
        $var_MigrationStatusLabel.content = "Import Complete!" 
        Get-ChildItem -Path "C:\plannermigrator\exportdirectory" | remove-item -Force
        $var_MigrateProgress.value = 100 
        $var_NewMigrationButton.visibility = "visible"

    })

$var_NewMigrationButton.Add_Click( {
        $var_GroupSearchInput_Src.isEnabled = "true"
        $var_SearchGroupsButton_Src.isEnabled = "true"
        $var_GroupList_Src.isEnabled = "true"
        $var_SelectGroupButton_Src.isEnabled = "true"
        $var_PlanList_Src.isEnabled = "true"
        $var_SelectPlanButton_Src.isEnabled = "true"
        $var_IncludeUserMappingsCheckbox.isEnabled = "true"
        $var_GroupSearchInput_Src.isEnabled = "true"
        $var_SearchGroupsButton_Src.isEnabled = "true"
        $var_GroupList_Src.isEnabled = "true"
        $var_SelectGroupButton_Src.isEnabled = "true"
        $var_PlanList_Src.isEnabled = "true"
        $var_SelectPlanButton_Src.isEnabled = "true"
        $var_IncludeUserMappingsCheckbox.isEnabled = "true"
        $var_NewMigrationButton.visibility = "hidden"
        $var_GroupList_Dst.Items.Clear()
        $var_GroupList_Src.Items.Clear()
        $var_PlanList_Src.Items.Clear()
        $var_MigrationStatusLabel.content = " " 
    })
        
##Usermapping Checkbox is checked
$var_IncludeUserMappingsCheckbox.Add_Checked( {

        $var_IncludeUserMappingsLabel.Content = "Make sure to complete user mappings file!"
        $global:UserMapping = $true
    })

##Usermapping Checkbox is unchecked
$var_IncludeUserMappingsCheckbox.Add_Unchecked( {

        $var_IncludeUserMappingsLabel.Content = ""
        $global:UserMapping = $false
    })

$Null = $window.ShowDialog()