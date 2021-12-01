### Example script to collect M365 usage details - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$days = "180"
)

### Global parameters
$ProgressPreference = 'SilentlyContinue'
$today = Get-Date -Format "dd.MM.yyyy"
$systemTempFolder = [System.IO.Path]::GetTempPath()
$export = "Cohesity-DMaaS-M365-Report_" + $today + ".html"

# Generic functions
function getGraphReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$reportName,
        [Parameter(Mandatory)][ValidateSet("30","60","90","180")][String]$days
    )
    
    try {
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/reports/$($ReportName)(period=`'D$($days)`')" -OutputFilePath "$systemTempFolder\$reportName.csv"
        "$systemTempFolder\$reportName.csv"
    } catch {
        Write-Host "Cannot get report! You need to authenticate using account with 'Reports.Read.All' rights." -ForegroundColor Red
        exit
    }            
}

function calculateGrowth {
    param (
        [Parameter(Mandatory)][string]$reportCSVfile, 
        [Parameter(Mandatory)][string]$reportName

    )
    if ($reportName -eq 'getOneDriveUsageStorage'){
        $usages = Import-Csv -Path $ReportCSV | Where-Object {$_.'Site Type' -eq 'OneDrive'} |Sort-Object -Property "Report Date"
    }else{
        $usages = Import-Csv -Path $ReportCSV | Sort-Object -Property "Report Date"
    }
    
    $sum = 1
    $storageUsage = @()
    foreach ($item in $usages) {
        if ($sum -eq 1){
            $storageUsed = $item."Storage Used (Byte)"
        }else {
            $storageUsage += (
                New-Object psobject -Property @{
                    Growth =  [math]::Round(((($Item.'Storage Used (Byte)' / $storageUsed) -1) * 100),2)
                }
            )
            $storageUsed = $item."Storage Used (Byte)"
        }
        $sum = $sum + 1
    }
    
    $averageGrowth = ($storageUsage | Measure-Object -Property Growth -Average).Average
    $averageGrowth = [math]::Ceiling(($AverageGrowth * 2)) 
    return $averageGrowth
}
function processReports {
    param (
        [Parameter(Mandatory)][string]$reportCSVfile, 
        [Parameter(Mandatory)][string]$reportName,
        [Parameter(Mandatory)][string]$item
    )

    $report = Import-Csv -Path $reportCSVfile | Where-Object {$_.'Is Deleted' -eq 'FALSE'}
    $summarizedData = $report | Measure-Object -Property 'Storage Used (Byte)' -Sum -Average
    switch ($item) {
        'SharePoint' { $sizingData.$($item).NumberOfSites = $summarizedData.Count }
        Default {$sizingData.$($item).NumberOfUsers = $summarizedData.Count}
    }
    $sizingData.$($item).TotalSizeGB = [math]::Round(($summarizedData.Sum / 1GB), 2, [MidPointRounding]::AwayFromZero)
    $sizingData.$($item).SizePerUserGB = [math]::Round((($summarizedData.Average) / 1GB), 2)
}

# Check if required modules are installed and if not install them
$modules = @("Microsoft.Graph.Reports", "ExchangeOnlineManagement")

foreach($module in $modules)
{
    Write-Host "Checking module $module" -ForegroundColor Yellow
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Required module missing. Installing module $module for local user...." -ForegroundColor Red
        Install-Module $module -Scope CurrentUser -Force
    } else {
        Write-Host "   Module found!" -ForegroundColor Yellow
    }
}

# Connect to Graph API
try { 
    Write-Host "Connecting to Microsoft Graph API...." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Reports.Read.All","User.Read.All"  | Out-Null
} catch {
    Write-Host "Cannot connect to Microsoft Graph API. Please check credentials!" -ForegroundColor Red
    exit
}

$sizingData = [ordered]@{
    Exchange = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        firstYearFrontEndStorageUsed = 0
        secondYearFrontEndStorageUsed = 0
        thirdYearFrontEndStorageUsed = 0
    }
    OneDrive = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        firstYearFrontEndStorageUsed = 0
        secondYearFrontEndStorageUsed = 0
        thirdYearFrontEndStorageUsed = 0
    }
    Sites = [ordered]@{
        NumberOfSites = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        firstYearFrontEndStorageUsed = 0
        secondYearFrontEndStorageUsed = 0
        thirdYearFrontEndStorageUsed = 0
    }

    TotalDataToProtect = [ordered]@{
        firstYearTotalUsage = 0
        secondYearTotalUsage = 0
        thirdYearTotalUsage   = 0
    }
}


$usageDetails = @{}
$usageDetails.Add('Exchange', 'getMailboxUsageDetail')
$usageDetails.Add('OneDrive', 'getOneDriveUsageAccountDetail')
$usageDetails.Add('SharePoint', 'getSharePointSiteUsageDetail')

foreach($item in $usageDetails.Keys) {
    Write-Host "Collecting usage details for $item..." -ForegroundColor Yellow
    $reportCSVfile = getGraphReport -reportName $usageDetails[$item] -days $days
    processReports -reportCSVfile $reportCSVfile -reportName $usageDetails[$item] -item $item
}
Remove-Item -Path $reportCSVfile


$usageDetails = @{}
$usageDetails.Add('Exchange', 'getMailboxUsageStorage')
$usageDetails.Add('OneDrive', 'getOneDriveUsageStorage')
$usageDetails.Add('SharePoint', 'getSharePointSiteUsageStorage')

foreach($item in $usageDetails.Keys){
    Write-Host "Collecting usage details for $item..." -ForegroundColor Yellow
    $reportCSVfile = getGraphReport -reportName $usageDetails[$item] -days $days
    $AverageGrowth = calculateGrowth -reportCSVfile $reportCSVfile -reportName $usageDetails[$item]
    $sizingData.$($item).AverageGrowthPercentage = [math]::Round($AverageGrowth,2)
    Remove-Item -Path $ReportCSV
}
Disconnect-MgGraph

Write-Host "Connecting to Exchange Online Module to collect in-place archive sizes"
Connect-ExchangeOnline -ShowBanner:$false

$FirstInterval = 500
$SkipInternval = $FirstInterval
$ArchiveMailboxSizeGb = 0
try {
    $ArchiveMailboxes = Get-ExoMailbox -Archive -ResultSize Unlimited
    $ArchiveMailboxesCount = $ArchiveMailboxes.Count

    $ArchiveMailboxesFolders = @()
    # Process the first N number of Archive Mailboxes. Where N = $FirstInterval
    $ArchiveMailboxesFolders += $ArchiveMailboxes | Select -First $FirstInterval | Get-EXOMailboxFolderStatistics -Archive -Folderscope "Archive" | Select-Object name,FolderAndSubfolderSize
    
    # Process any remaining Archive Mailboxes at the pre-defined $FirstInterval
    if ($ArchiveMailboxesCount -ge $FirstInterval){

        while($ArchiveMailboxesCount -ge 0)
        {   
            $ArchiveMailboxesCount = $ArchiveMailboxesCount - $FirstInterval
            $ArchiveMailboxesFolders += $ArchiveMailboxes | Select -Skip $SkipInternval -First $FirstInterval | Get-EXOMailboxFolderStatistics -Archive -Folderscope "Archive" | Select-Object name,FolderAndSubfolderSize
            $SkipInternval = $SkipInternval + $FirstInterval
        }

    }
    
    foreach($Folder in $ArchiveMailboxesFolders){
        $FolderSize = $Folder.FolderAndSubfolderSize.ToString().split("(") | Select-Object -Index 1 
        $FolderSizeBytes = $FolderSize.split("bytes") | Select-Object -Index 0
        
        $FolderSizeInGb = [math]::Round(([int64]$FolderSizeBytes / 1GB), 3, [MidPointRounding]::AwayFromZero)

        $ArchiveMailboxSizeGb += $FolderSizeInGb
    }
}
catch {
    Write-Host "Unable to calculate In-Place Archive sizing" -ForegroundColor Red
}

Write-Host "Calculating Exchange Shared Mailbox sizes" -ForegroundColor Yellow
$FirstInterval = 500
$SkipInternval = $FirstInterval
$SharedMailboxesSizeGb = 0
try {
    # Process the first N number of Shared Mailboxes. Where N = $FirstInterval
    $SharedMailboxes = Get-ExoMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited 
    $SharedMailboxesCount = $SharedMailboxes.Count

    $SharedMailboxesSize = @()
    $SharedMailboxesSize += $SharedMailboxes | Select -First $FirstInterval | Get-ExoMailboxStatistics| Select-Object TotalItemSize

    # Process any remaining Shared Mailboxes at the pre-defined $FirstInterval
    if ($SharedMailboxesCount -ge $FirstInterval){

        while($SharedMailboxesCount -ge 0)
        {   
            $SharedMailboxesCount = $SharedMailboxesCount - $FirstInterval
            $SharedMailboxesSize += $SharedMailboxes | Select -Skip $SkipInternval -First $FirstInterval | Get-ExoMailboxStatistics| Select-Object TotalItemSize
            $SkipInternval = $SkipInternval + $FirstInterval
        }

    }

    foreach($Folder in $SharedMailboxesSize){
        $FolderSize = $Folder.TotalItemSize.Value.ToString().split("(") | Select-Object -Index 1
        $FolderSizeBytes = $FolderSize.split("bytes") | Select-Object -Index 0
        
        $FolderSizeInGb = [math]::Round(([int64]$FolderSizeBytes / 1GB), 3, [MidPointRounding]::AwayFromZero)

        $SharedMailboxesSizeGb += $FolderSizeInGb
    }

}
catch {
    Write-Host "Unable to calculate Shared Mailbox sizing" -ForegroundColor Red
}

$sizingData.Exchange.TotalSizeGB += $ArchiveMailboxSizeGb
$sizingData.Exchange.TotalSizeGB += $SharedMailboxesSizeGb

Disconnect-ExchangeOnline -Confirm:$false -InformationAction Ignore -ErrorAction SilentlyContinue

Write-Host "Calculating storage required for Cohesity DMaaS" -Yellow
foreach($Section in $sizingData | Select-Object -ExpandProperty Keys){

    if ( $Section -NotIn @("Licensing", "TotalDataToProtect") )
    {
        $sizingData.$($Section).firstYearFrontEndStorageUsed = $sizingData.$($Section).TotalSizeGB * (1.0 + (($sizingData.$($Section).AverageGrowthPercentage / 100) * 1))
        $sizingData.$($Section).secondYearFrontEndStorageUsed = $sizingData.$($Section).TotalSizeGB * (1.0 + (($sizingData.$($Section).AverageGrowthPercentage / 100) * 2))        
        $sizingData.$($Section).thirdYearFrontEndStorageUsed = $sizingData.$($Section).TotalSizeGB * (1.0 + (($sizingData.$($Section).AverageGrowthPercentage / 100) * 3))
    
        $sizingData.TotalDataToProtect.firstYearTotalUsage = $sizingData.TotalDataToProtect.firstYearTotalUsage + $sizingData.$($Section).firstYearFrontEndStorageUsed
        $sizingData.TotalDataToProtect.secondYearTotalUsage = $sizingData.TotalDataToProtect.thirdYearTotalUsage + $sizingData.$($Section).secondYearFrontEndStorageUsed
        $sizingData.TotalDataToProtect.thirdYearTotalUsage = $sizingData.TotalDataToProtect.thirdYearTotalUsage + $sizingData.$($Section).thirdYearFrontEndStorageUsed
    }

}

# Calculate the total number of licenses required
if ($sizingData.Exchange.NumberOfUsers -gt $sizingData.OneDrive.NumberOfUsers){
    $UserLicensesRequired = $sizingData.Exchange.NumberOfUsers
} else {
    $UserLicensesRequired = $sizingData.OneDrive.NumberOfUsers
}


# Report HTML template
$HTML_CODE=@"                            
<html>
<link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
<head>
​
​
<head>
    <style>
        p {
            color: #555555;
            font-family:Arial, Helvetica, sans-serif;
        }
        span {
            color: #555555;
            font-family:Arial, Helvetica, sans-serif;
        }
        
        table {
            font-family: Arial, Helvetica, sans-serif;
            color: #333333;
            font-size: 0.75em;
            border-collapse: collapse;
            width: 100%;
        }
        tr {
            border: 1px solid #F1F1F1;
        }
        td,
        th {
            width: 13%;
            text-align: left;
            padding: 6px;
        }
        tr:nth-child(even) {
            background-color: #F1F1F1;
        }
    </style>
</head>
<body>
    
    <div style="margin:15px;">
            <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAARgAAAAoCAMAAAASXRWnAAAC8VBMVE
            WXyTz///+XyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyTyXyT
            yXyTyXyTyXyTyXyTwJ0VJ2AAAA+nRSTlMAAAECAwQFBgcICQoLDA0ODxARExQVFhcYGRobHB0eHy
            EiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AQUNERUZHSElKS0xNTk9QUVJTVFVWV1hZWl
            tcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9foCBgoOEhYaHiImKi4yNjo+QkZKTlJ
            WWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc
            7Q0dLT1NXW19jZ2tvc3d7f4OHi4+Xm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+drbbjAAACOZJRE
            FUaIHtWmlcVUUUv6alIgpiEGiZZIpiKu2i4obhUgipmGuihuZWiYmkRBu4JJVappaG5VJRUWrllq
            ZWivtWVuIWllHwShRI51PvnjP33pk7M1d579Gn/j8+zDnnf2b5v3tnu2g1/ocUmvuPRasx83cVu1
            zFB5endtWUCHgoM/+0y1V64sOZcXVlhMDpWXdLM+PmPnmdZTVJeLCPiL6Jd9jT6nfo2y+hH4vE/h
            Fcj6bP6uhcqxvxfYzOdsxOb6gYm39qdrRmE6bBxB2EQWHOXfLBvVvMsIqWdBEYzYvcgWRJ6nS3f5
            +/YSWXEQVeYJPqpXx5XkaaalFuOu22h2E5UVkrIadaAyXFXTwbKh1cw0J3bCgvzFO/CRWtuk3IjP
            lKYK23C7ga3IFCblPwp1HrNvUAyH1W0tRzKlIbk/OmbpbX04uNHGp1/9j6MxMMxUNSYXbqoTJWmF
            t3yCqqHGVLzJK2l8qTtoOzldBqD/C/Ra3hDgOYZKTU2awmpZgVbwG7udWGEvovHYXFHIkuYzHECN
            Pzb0VNy9g8/60KVh5X/QbwtRCajQH//GsQ5k7KCTzqQGprVrwW7HC9GOKQQMhpP30UpWiIM0XYZQ
            gcsYR50Mo9vj73vS9+sOy1Vl6A5S7auXJ53v4Lpr2Trf9LcN0utNsZ/K9Ra4iy++XGE+h3zGGQaV
            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
            8LK0YAAAAASUVORK5CYII=" style="width:180px">
        <p style="margin-top: 15px; margin-bottom: 15px;">
            <span style="font-size:1.3em;">'
​
</p>
​
<center><big><big><big><big><b>Cohesity DMaaS M365 Sizing Report $($today)</b></big></big></big></big><br><br><hr>
<img src="data:image/jpeg;base64,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" />
<br><br>

<b>Total Size: </b>$($M365Sizing[0].TotalSizeGB) GB<br>
<b>Average Growth Forecast (Yearly): </b>$($M365Sizing[0].AverageGrowthPercentage) %<br>
<b>Number of Users: </b>$($M365Sizing[0].NumberOfUsers)<br>
<b>First Year Front-End Storage Used: </b>($M365Sizing[0].firstYearFrontEndStorageUsed) GB<br>
<b>Second Year Front-End Storage Used: </b>$($M365Sizing[0].secondYearFrontEndStorageUsed) GB<br>
<b>Third Year Front-End Storage Used: </b>$($M365Sizing[0].thirdYearFrontEndStorageUsed) GB<br>

<br><br>
<img src="data:image/jpeg;base64,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" />
<br><br>

<b>Total Size: </b>$($M365Sizing[1].TotalSizeGB) GB<br>
<b>Average Growth Forecast (Yearly): </b>$($M365Sizing[1].AverageGrowthPercentage) %<br>
<b>Number of Users: </b>$($M365Sizing[1].NumberOfUsers)<br>
<b>First Year Front-End Storage Used: </b>($M365Sizing[1].firstYearFrontEndStorageUsed) GB<br>
<b>Second Year Front-End Storage Used: </b>$($M365Sizing[1].secondYearFrontEndStorageUsed) GB<br>
<b>Third Year Front-End Storage Used: </b>$($M365Sizing[1].thirdYearFrontEndStorageUsed) GB<br>

<br><br>
<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAZ0AAAC0CAIAAADAaWa/AAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAhGVYSWZNTQAqAAAACAAFARIAAwAAAAEAAQAAARoABQAAAAEAAABKARsABQAAAAEAAABSASgAAwAAAAEAAgAAh2kABAAAAAEAAABaAAAAAAAAAGAAAAABAAAAYAAAAAEAA6ABAAMAAAABAAEAAKACAAQAAAABAAABnaADAAQAAAABAAAAtAAAAADq9Rd7AAAACXBIWXMAAA7EAAAOxAGVKw4bAAABWWlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNi4wLjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYvMS4wLyI+CiAgICAgICAgIDx0aWZmOk9yaWVudGF0aW9uPjE8L3RpZmY6T3JpZW50YXRpb24+CiAgICAgIDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgoZXuEHAACAVklEQVQYGezBCbzmd1nf/c/3+v3+932ffc6ZmcyeTJbJRiAByipLEMqi+FQEEamgbaEK1Vpf1La+Hrv76FOtrdYlChVFaUUEKiBKEYhhFR9ICNn3ZfaZM2c/517+/991PeckkAUIGEyGZHq/34oIhoaGhk4hxtDQ0NCpxRgaGho6tRhDQ0NDpxZjaGho6NRiDA0NDZ1ajKGhoaFTizE0NDR0ajGGhoaGTi3G0NDQ0KnFGBoaGjq1GENDQ0OnFmNoaGjo1GIMDQ0NnVqMoaGhoVOLMTQ0NHRqMYaGhoZOLcbQ0NDQqcUY+voCgqGhocehzNDX8AhRRIA5ZhJDQ0OPH4oI/o8XEZK4R0Q0CBAkXBRUMTQ09PhhDIEkICCCgMr75gMTgTyMoaGhxxVFBP8HCzZEBIEZIMApOKbwEJaMoaGhx5PMKSRAbIhwiXWBQME6NwIsCI8AKWQKSaB1iBoWluvu2tpnb5u/5KzN520fFwUCxNDQ0ONH5hQS4eEuKWTBuhKRAnDcw3IIyT0lQSDVxFqhuzK49fjq3SdWbzyw/Gd311+YHXCo+5f/Yvy87RMRJjE0NPT4kjmFSLhAEAVXbbmKSNEnBakFCZo+zd2zPjfXX2niqruXP3Fw9ZrZ5TuPDeiJwYCRfMFo54YJGx8f4R5BCDE0NPT4kTlVRODhES5sHUQbRwraJ1ab5ZW1I4vNJ29evn62947jqxxdYaWgTErkZnvO7VHV43nVvdv0GZR+fwBjESSMoaGhx5XM41YE9whJgERSgtzzGAx8aXnlpuPN0cXuXcd6V9zd/d+Hl5gdYB0olWlPlZmytWDFvaaapQk1xUFMmQB3Z0NEuGQMDQ09fmQeG4J1EVAgg0IuBIoIJAiFEwQGHpIwiQ0CGji2vHbwaO/oYv3p2+c/fbh86ng/1nr0g4FTcVontaeq2kttzWrEXVFRE9Y4oCRPeCWhEliAG2KdNjA0NPS4knkMiAgIQnIychUMw8IdohYJpSDJkCCSvMGOLvTXVvuHV+Jzt8/ePLty9aHmc4cLvR7mVJXJtmRvjxJjWgnmvGkKYJQKRDhyIiERhJx1gcQGScG6EASIoaGhx5HMY4AURAyAbOY1JAXyWsnAWgSkVWdQx8rK2vWH68PHF2850n/fXas3zvboQnFyYOxp5dxpLxOrpfEyOEEKJ7iXsSGIQEIQ4qEFG8TQ0NDjT+bbKkDQOAEJVBpLCQSqI63UaXZudXZ55dhS/PVda58+uHbF0VWWnX4NDe1qTxWMqy6poWnIxxkMmiYiIQslAsQDiA3B0NDQKS3z7RDBOhGSgGwGAdGQ755fW16pbz3a/fSdy9cf7l6/2L9rdcDSgMZot0Yqpqu61faCLRSOhkqNK2SGh8JCGYlAEAQBEveKQEJAsE4CJEUEQ0NDp5DM307g4ssK4aHMughZABGiUahgARbIDMkUUCCvNAz6Td34LUeXbzi4ctuJ/kfumrvqQEMPKggnsTsnG233TCvRDMKPROWe2NBIHkgBBbdAggQBAQHigQQEDxYRDA0NnVoyjwARgWThigjJw4kwx5Uaqyp5UhEJUgPdgR+dW75l3m8/vnrl/u7Vx+ovLHZZWKFuUUNVTh+VT6rrTY3V2FGKB1G4hzlB1GxQhEGEIhABBARfJh6SGBoaOnVl/naEASFFBJ6ARo1MFRkrRsmokA7NNydWewfmVj572/wNx8vHDq0uLjas9UiiZZ2UprNV7aZxlqkOhq+DFBFEMQUIRAiEAsSXBUNDQ0MPlvlb8NhgWgcSyUW0qPq1n6iXZpfTNYfqOw/OH53vfepo76+OOYsrVGBGlfZUpUyNdIMuUcKOOBa1RxOJDaF1rFM4AoEQEAwNDQ19Q5mHIyJAKAgkmYQEDJygHF8qNxxeWVruXnNg8L7bl6852qPnuFO6dKo9STbTWi2lxuuoD0flJSBQSEUGCFWGghIoIlgniMSGgGCDGBoaGnpomW8qmlAmKF5yCkisE92IQ7MLc0vlmoP9vz7QnVsrtx5fvmq2Zm1AQLu1td3kkZJDhfZapGOKpnZQRIIIlTBABBskAlCEwNgQrAuB8yDB0MkVEeAgJCGGhh7bMt9MUVKE0STFsV5eXe7ecmj5mgOrNx/rvnV/j/lVen1ymzrRTjtz0xnPXVgi5sM8LAgCyQVBBEgEBOJeAkRwjwAHMfSYEUTgwboQCDE09NiW+WYEigZpzfOvfvjWn//YcTwgoaaqYnca605azxoP1Q3HoorwiEDufIUIQijYEHxjYugxJcKbEpZMUjgmEEOnhAgkTj2Zb8ZiXcE6/aa+9ljBY++4DVRKM+gp3cmailOEByZXA0IBAQJBsCEiGPr2CiCAAAKJrxDiIUnKVYsvE0MPLUA8PkQgIbEuAolTSeabcYRVDm2rJ7OTbDHKUimuDiGoQxUB5qJAsEEgHkhBiKFHWbDOhQIp2CCKhxlCAgQIEA8UASUiB8gQ94pA4qYja5+8/thouz3o96dnJl7yxC2dRIAY2hCEIkImXAjEQwkgAg9MrJME7shCiEedR4gIGeEmA5/rlZlOlhQRUoBAECBOioiQFCAeSZlvxqTADJqoLITXCnPlCEcQRjj3CATiQYJ7hTH06IsIhfehUm7KQDJLKRl18UETi93B8aXuwuqgqDKiqqrJsfZ0R5s7pFarMiPWakaNSAiICEm3HFx+42V3sj2xMHjeUzZ/5wWbOikTIIYC+l7a8vBWQ7iUIPg6BEFIkUliXSkRpSlVeMltYYlHWURDpFJq0UmDu+f0+3926+Vz9aXbR374hXtO3zwSpSHlCBmOEo+yEmFS3AOTEI+czN9EgFgXrFOICDYEQ48pVrxYRpRSV0koH1tave72hU/c3vzptUevX+qtkWmcKERGQWqy/JLNY3/33Mmn7930wotnxlJRgZxYJ9ZVSWzNT55KV1nsHk0SQ/dRREsaRG4btx9a/rmPHNwzXtUlxAMIAizqGEy3O+dvGd06Xs1snbhgR9XKaRBVNLSzI+PRpUwJqzoaLPebn/qjO953xbFNp8XHvzD60f0rf/JPLp7uVB5EBOIkkCLCBUEYiUdU5m9CPEhABEOPOTFILtRu+lTVYpcP/PVdv/npub+6dZF2s2m8vcMswr0FQYu6VeW+50MlPj9bPn/HMn7w5l945r7TWn28zf0CaKJbghKNM/RVRCAD+muDd7z3MGe2qIN1Jr5KiLLKyiFaNdvH/+Ge0Zc/a+cLnzAx2UruZuJRFRRFaZSTqqMLvffdsXjRmeOHGz97R/nEnQtHTyxP75omwkwEJ4GIQI2XZCkcGY+gzNDXESKA4PEkkMJSFKr21Uf6b/kf137sugWm7OJt7RPePnBssBCwSSSwEeo15mvqxITtHCmnbR18kdFcCriFMfQ35spV6ZPalhObq4sm0vGaQfh8L4jgPgHGznHGt3TGbGS+V95+3cLb/+rYq56y7V9939lPPX0sAolHTwiiSlGjKlcVqbu/b9PtPFeLFO12C5BKRAKJR1eAQhKWq4GXbCYeSZlvRYA4pQSIewnULpYBBS4EigIRpJAULgIpaIgcMgHhgGR8WwmzxHVHupdcdiXHy75tE/1+++qFBbbYZa/eedaW9tjM5GhLCa3VrC4uzS4277+1+4fXzR1aaJgwchWEGHpYgntEgNMvOlp8b7v9yvPbyXJgEAGVNNf3dx1Y4kSPRnTyOdMdn2y/57Zj7/nFuct/4hmXntcOb6TskiEeaSIhjEI0Z8yMvPO7L/qh371tsb0I1Tt+6IIztoyBCwuQjEdDEKyrPZQsI+1fLl+6+eAog0ufenZESOIRknn4glOOIACxIYieeQ/GCBxLxCCE1FIQDShCtSOlHEVyLHkAkcS3UQSZMrsS//gdN3DCz5hsLXh9vAx+81Vn/sBTtk5Pt0XmQSbBX/5c//nF/p9+bv9PfHKuV4cowkAM/U1IwkULEAknJ2O1e86OsZ95zUW7R6wEYkMEjftv1925Vb/i5pV3fPKOy29b3j7T2TU2tdTUL/itz33xLU+6ePeMl0FApJZ4hAkQUAUIXv2c7U/Zq5uPVufvau/blox1hjAeNRGBB8Wsc92Bhf/2kQPXHFr+7OcGv/b6rS94angg8UjJDD1YCIJGVZALTfJaObeUIPq+zkzRStZC0PewElmBQOFEIPFtYhFYet/n7/zMjZy7NS3Kj891/vxHt770qWeUaBpXgiAkhMLrohTQSeyd6fz4y87/jouXT5tIUCEHY+hhCBDrwkXCc9vrzRq0rE0IsSGcHN4amRxj72mTL3nq5l/9i7v+3z89smMyRqtYXrP//KGDv/HGmREVI4sA8egQGyrngt2bL9idoNS1lJF4VAUlpCgtGbfvX3jru++6+JIpdtIZySAIHjmZoQezgGq008pi0Eq5j+2f6x44NH9gSVceWFqqNZk5b3tn7+bO7q3TZ2xJneREP0ieWgHi2yNAprnV8nuf2c+49zR+9MTCf/6unS966u6mrhXJKhNhEhAEqaqiiTKISG4tK/0n7xzz0njxknJi6Fuihigo19YZ0AqiIcQGERYUkhPuve2d+HfffXbd9V/+xIHtGj1zYuSdVx37x7ccf+55072ihHiUDYzk1kDGUg7Eoy1kDVQIBqPJ2DHT6Rj9XimFR1pmaF1wHwGlGbMaxj5+y8r7/vrw+/f3Dxxco4D1UVCgCaqKXaP/eGd+xdN3POvcmalc8IIlvk0ikLj9+PJnj+Xdo43ok/L3/p2tmWZAk1uj8pAMCCJAHo5FHonAKcnM636TWx0nUyDxDYmhrycggRWi1jqUQGxw4RE5ItRI1pTUzuXHXrTnl79wbNltVKt4dfW1x5573kxWQIB4NGXqaCwlt0ikIhyMR5MoJrnCaNWI3oo3I5CSJR5pmSGQFAEEEBKi8dwj/acP3/6Rzy+MzHBWR0VaUXYi4x2Shc0eWX7rgfZbv3Dzm54z/c9fuu+sKWvCvZSWLJQaNZUyJ00E0tJCj4VmbGee7wVb2nkkQeVVLqWurEKsExKgABNIASrkKkeSkWQED61QAisoeeNSRAIXhBBOyEk5mqBSCrxB6yiRBSbu4xGiKHBLEYooFiE8rAIULskjUBIlsACPyNrA/cK9FOUUA1QVcMekxABVBLVQRPbiwhQU8ypZYF4ieU0rhzshzCJCRjSOIUsUsU4lFAxQS2ByxxLioaSMQzQVJUWByviyRLBOSFWIIjz89JmR//C0Hf/m40fYVJG7Hz/G63ox1cGR8WUB4Q00ohUSOGGoRISoQmGEQkSEwsOxLIkIhCEeSskkQvJwIplM3CfCS6OcokY58BJKKim8IZuFezFZeEIYIYkgwAOJMBdSmEMQGWsAubmDFY+cUBTyaBCI8AQ4EME9IrwoZSFvkJAJ8XBkhiCC+ygCCVHB5nbFpmqyxd1OcYIgwsKUECW385ZWPZF02RWzn7lr9bdfdeYz9k72Vbl6qJU8kTjJ6v6Afl9qD6KhSSUEqWr6A1kl44EkcS9BSgJaxr3EQ4vG1WogBrJ2MbJDcgaGQFJO+CACekZClUOFK4pZ4j4RpQyaVKl49kHClTNUgPDAQwRmMgj3ZoBEqqJXosqpxQNIJi+WMoRRMAirUYqCl7YqkhULIxWoDLwXpEKlOnIuhGe34qVJOUWxJMMcAgswlAS0YtBgKZSEk8Q3pnWGBIQQ9xIS9xCkoHFv5eqSPS2W+tXU6Eg7/a+jS7/WLVOdFgHiyyJQ6jsZ5BGqq2TQQjjFaISFsjARgqh7YRXKavpUbR6CJYc60cKi4asImbxYShAQKUooNe5GNBE1uSOlVIIclIKklFBi0C/ZGovU5KhFyxT4IKWKCKXKKKQEKGX6C9IEtJMKeDaBuJcslS6WCwKzEOJhyQx9rUDIoQSUqAMP7iUJFOugpplN7fl+vXuidfWR3jPfeusXf/KJF++o6lKZNeYtEidZ6lSMtuummWyxsNxNpYbKI2VL4GD8rQUZryIG7aS1ZLceWr776NLNxwalWCenvWM6e9fozu0TmzotmiasSNaEWQxAYNxLCKqmttw2ZY/6ztlmZWHh4EK5bX6w2u8nabRTnbO12rNl7IxtrZFUuZfGRnM4DxCoONmaO5dI4UQM3LaPllarwt1y6/ByOXD3sS8eWT26YlOdwSVnzTzrrAlTNClkdeWlpJFVfESDKtmKp6MH54/M96471l1aq6W0e3r0jC2trVtG9860E9H4wFjX4hsL7hcgvpYUjXIFmyYqJlrFfbxqdbupeAMVG8Q9BAqvkFEsC1pHV+u54/NLS3HjseUjay5pciT2bGrtmOhs2Tpz+kwHtFo3HeMbOLFq3UEy1X3yVFVmxiwwsSGguLI1+5cJD0VTyNPt0ulUBC1FSzq23DtwtHvLsbX9c03BZkbtCbtau7ZuOn0Gj2KlagypZMwNommKDq16K/ruao2OHljuMTq2GqPY2oHu4EjXm14jEyCiF7ZjTJ2UQLgrJR6mzNDXElrHPSIIAcGGgBAEIpxkpUvVOdD4zkqH1tKPv+emP/zBc3dvHm+KPHsicdKIdTNTHaZsOawdNYNyxfVzr982GTRVFCjQ5m/HwK2E5eytz9xw5LJPHnnndSvMrzI2hjsReEPLXnvh5je8YPvznnBaalaTzG0EyzyYKVtO88trl1+/+Knr5/7rnWvcvUIYHZBoBJlel5nqRy6e/tHn7XzaOTOtUocSD6CILG/U+o9/+KW3H64vaqdrF3uXv37vpRfONJb//Evzb/nANTfdJqrESMMsz3/C/Hv/+TM3t0ryxqj61kqlGbMyiPyZ64794Wfn3nrDKkdXGKtIRhiDPv0uuyd+9pLTvu85uy7e3cYJEN+QuJ/4usLdFIBTkYQsmoZOy9ggxH0Ug+KVVbLmxmODD//1iY9cd+DPD/VZClotBGa40+0jOHPs3++b+HvP2nbxmVtwi0Diq7iHmd5zxd0/9olDz99sVxzvv+27zn7DpbsVINYpSDhqXfbB63/hhrWnjer/Wx584PtOf/nf2SLlY2vx7ivueOdVa5+7+QTZaIkGEGurnDn1i0/b9IYXnjk9RmpqqdMkEdnEieXu0377lm31wMxGVA72KjZ3bu0u2ab0C1cvv/3WzxelYMO42U2La7e95SmnbzGiMYNwZDwcmce0UERI3CtAgCDYECAQjywJjyAASUBs4MsECoLgXu2IvpQONyOnd1Y/9aX833bs/4VXnm2RIkCcNJIgztg29uSZ6qrZ/nRlk5PtH/6zQxfv23Lx7rFBqRXtSnyLJCSIQUSH7FF+7c9v+akPLaHuBaP5ti1jg+I7M5PtkaD2pv8/b1z5n1+47tdfv/KPXnBmp9Q4sgDjPkGk+PMrD77hAwcPHVylHWe1W5Pb2/3g9n7pO4ymC1puaXRt4L/3udnf+9T8216/90cu3RPeZEx8WUiBEqVe6nOk2x8PZq1uBHrHZw6+4XdvnhrvPGGbruv3WsqDzeXCmZEOhcCJIg+UU7lj0X75T27+jc/MYn7eVLuzd2y23xzs97HYN1WNVpuOr9Y/9/FjP/fpw+/9obO+9xm7RUQgQILgW6KUaPpYrutCt7ZxawDVJoECxLoAlbBWjuW+/89PHfmxP9vPQsN4vnh0QqN+qMSxwQAvu6pq0+aRpPrgfP1vP7Hyb69Y+NW/t/D6F+7b1CYiJAWIAPEV3uty9/Jxm+JQYVDzACFcJMJXBhxaXdrS4uDiWi3Ruu5I77W/c92X7lyYmhjdt7V1y8CxdPaYV63kmppd7f+LP5l995cW3/VPLj57uhp4YyQLN6nvzM53x5r+go1R9+vcM+Um2i6oozsXRMM9ShJzjUHGSwyCdpiJhyfzmCDJ8AjCFCjcZRiEzEtkNgQKQSAkoggIRIQEBOuC4H4Sf1MBAgUEDsiB8AhEmMIhAol1AeJezrosItQ/GHnvZP1Ln1959dP7f+f0ido9cfIISmhmpPUvn7P9NW+/ZeuuyUNljUH1urde89bXnfvMfZudJhp3s4ZcqQh5yEyEQ0iJhxCCQKzTpDGQX/and/z0Hx9tn9buL+mG1shLtuUJmvcs6NDdK7TZMdE5bTSmx8Z+/J13nDaSv/+Zp6eyhrcxIe4VyLDf/ejhQ0e6T9k+cuVy//Y1Z7lw2tizd9iuVOYHfPTmZUreNBW7pltjXt749ls2j/GKp+0pQRL3EiAJb2Uje+pk0mCkNfrp21be8Ns3zGydnFtZWZyYfM2ebV2tvv+W+rrF0i+0W5YY1MU7uXPnbPPi37nt1hsPnrdzupTmpsWGwerM3qlXbNm02G8+fmiZowPGOH9rfWJgr7zspnfU8drn7FEMzM1NSQ1qQfBwOSGDmJ8f0LilWFhrnnvGpvZoC1TcXcoMBp5aOR9f6P7MH9/2O59d3DHN5m2da3uDq2dXUfu83fmZWybl+fLZ7sEjy5AZz+fPxFpp/eS77vjMYf+tHzxz02huCp5ohaOKr5DESO4oGDUhHkAgGUSVjco7Gdqjmzv56InBRb9+JSeCdrXYW4s9W14zyYle+YsDPZYaRstpudq3TZ8/EP/gv3/xvT/+lK0j7aYUMFAQ9Ad39UArlA6dwXhVVtL4SPS7/W6vn0kQARxLohvZa2gHbUUEiIcn85jgES5LOA5EIwllB8xyuCIID+7hhhRKHgQecu4VwTqJb4EguJ+EgAi+KQcF66IE/VSxtPKnVx558p6JLHFyCTwGL3/Wtpdeu/Tha+f2zqS2+zUL8axfuek3X7ntB565bWZ0nGiiDFzKZsmIcBAYX1eAwJ0Irxtc1p743U/P/vT/vovxiRfvth9/8UVP3DnabmdRfr3mwInFX/vYkXd8+sTO7dX+uteZGnv1+w/fdd62PdOtuiktGYivEOXMTRU9v3KhefWZY9958WnPv2Bm82hNexSZSllZ6f359Qtv/tCRhaa3Ta28Rd/33v2H981s3zQWgcRXCHAEabWpaJdjc8fe+8Ue0Tpnc/NzP/y0J+9pl06uIvq9cmit28l9Y4TSyjkdWFz7yd+++taD5bxt4zet1tT6d8/f+srv2DY92R5tVwot9so1++d+/kOHPnugPn3Sz9kx9sNvu2Xfls6zzt9aKBHuaoPz8A2EqeoO1j5443E2TRSc1fq7zxjb3CFKH2uVkKha2ea6a298503vv7K3b0u7zv1rjy+ft3viZ1+x6zvOmxhtp5xHstEMekdXyuU3zf7q5YdvPNbs2ZzP3zX+R586sEX+C6/bN5HdXcVaifsFAkoEpTj3ChAPECEir3lNHtw237znr27kaM1k9X8/d/cPPm3r1onKWjaIKGvNp687+oMfOXFsca2M2L4p++T1q+++4uCbX3pWVhQlKFOj+W2v3teKpnHGqvRXtyz8yl8d3T2xemBx8P1PnP6ep+1Ur5YJMGl54J2RjpNQn2grAomHI/MYYILwKErJ2tK4WinCIoho6rqOKoRAUpKllogiNRCO9SIvu3uAmSKAgOBvJ/gbE+sikIBjbmMj1b+/vv9jLxxsn2hFIHHSGFGKRtudX3v16S+cW7nziJ+1KZXsE6V58/848LZPL/yrl259yRO3TnVaBSseFi6Fh6TMQxPCvE6Zjl1x+5G33zygr196+cyPvvT0iXYbGrAI04htm9z6q/9gevf4Hf/PR4/tmFGr8ruOrn38+oUf+Y7NSQnEV4gI8vVz5annjv7X7z3jonM2T7cqcChEoHA6W0btTdtG9m7ufNdlN3bHytkt3XSk/PXN8//X08cgQHxZsC5YN2gGjLb/+Orld92w9L1Pnvq11523e8so9KEhMiNp+/Q04SoDz22P+C/vu/kDt2vf9s5dayuM6WN/f99zL9xVMYAECWLTSHXG9I6nnjP9U7/7pT+6trd3kzFd/acP3vl7OycmJ/CQghDfSID4Whb9bOlTd/T/4Itzu6bGu43TnnjG+ZsgNeEWBeXkHsSvfuCu91+5sm97a9Cs3DVr//olu9/00n07xg0cckSRjJGxzVO6cNfUyy/Z8+/+6Ibfu+bE7qmJ87bZb3xq8Tln3fWaS8/wIhOIB4ngHuKhBMSq28g4/+xjR3vdFcZ1xY/sfd4Td7LBa6yiGyOjr3ne3gvO3nLJW2+aW25Krtmy+Zc/ceQ1z9m+ebxdQlZ8uqN/+OydRgQITVf6lT87un2GA2v2gtMnXve07TxYce87bSKEEA+T8W0TfEUESTadbRcx6PaPLTSH5/zgiebgSjoaU3M5z2ebq+yEdKz2wyf6h483h2bt0InWkXktdJttJXYYoxKgQNxDnFQRrDOf8sKJ7tV3L3DSBQpTrwzO2Tp++Zuf9MyzJ24/ujTd1AOxdyZdNdv/gd+8/fWX3fqhq5fXeoNkFkrFMbOI4OsS66REELgZK4OGo/qXL9vzz77nvIl2LoMyKCnCCErQd00l/+d/7+xnnpMO15RoMdJ87osHIkzICe4j6hi8+Tun/9dPPvW5F26dSu6lV7t6pWqoSqj4YBDqeX7Zk7b/x+duWVpqBoLR7nuvXXWQxH1CfFk05DGr33XDKmPpl157we4tnV70+55L6XiwFmVQN9TeuAy//JoT//XTC+dti+Xeaq+M/sUPX/ydF+5SXZqmGjh1GXjped3vNewYbf3iD13ATOdgt3vO2Pj7b+5//vZjpo4iXCEIHkisCwi+Lg/wyNbev9z81B/fwWjLxIHu4HvP6zztzPEGpVQhzBtS/syNJ/7D5fPnbI5uNHct6d9+1+k/+6pzd4xTmuhHbrwu0a+j7jn9UnvTP2NG/+2Hz33V+ZsPLK0teb1lpv+DHzp8x2Lk7BHOVxPfhMBRZ2Cdzd1VCh//0Sc874m7+nUpxZtiNINeaTVeD0pcvGvqL75/VyysTub2nhjcscCVdy5D8ghMJUzR1GVdDZ7cyS2FYWo1BZqmqb3UXmovTZSewltCyiYPgocp8+0hwqQSCGkLIdex1cFcv2Hv1D/Z09o10zlzx9Tu6Wp6rNWqUhLCB030CosDn1vqHj7RO35ieWHBrzruf3lskcXCaGp12k0U7hUB4lEXIO4V4R6tnOn2Ds8uw2mOpzAgFBDCeDRJSLS96Xt11pb2B9904X+/vP0zHzhBy84YHewcQSP5A3fMf+C/HPqeS0778Uu3P+uJ2yZyVUoTSoYXzFjnikCJ+4kwhabg6CBdcjr/9MWnZ/V7XrWqqCAibB2eUVPam0b0luef+f2X3dDZYeTJqxaaQ8tl56QRIHGPQEbrZU/f6zR13SRLWM6EUQQiJ0oTxRRgL3rG9n99+VzQotW/a/9Cf9CMtHJESEQI8RUyq7datbrS/PErTztnWzuaukNqkhdTyy17tooSBdpL3f5ll99Fpy3FkcX0P141fem5000ZpJRcYTSmXGiZ0YrSb/z0qfE/ePGu1/3+XdXIIvj/uqn3HRfRxhowHkjyBgwhFcjiq4RJSDfffeKn3n3r5w8P9oy22hLL/tPfc9ZYqwpvwowwTLX7b39qltz0c/vAYvPaJ2z5qe8+o4X3PVU5qlIimcdojkiqw2xA2wfNxGjr539g33v+8xeOlTi91Zmd7V5+5cEzX3C6xLdE5vWu5HfPN7/1itMvPX/GyyAJM7lMXllgBqWB/Mx9p7304tkP37FwfgvWdNfhHhdFIkAhI0qkSmUAhvdpetgYlDBBJoFYJyhkKJkSYYQw8TBlTiqxIQTJrInoyDeTDi4mWvUbnjr5fU/ffe7pU9snWyMJQ2xwMB6kgUlQE9E0ZW51cMtCc/Ntax+74eY/urUZqawfhUjgCBCPukBig1uYKlFwOhDh7niYKRAFGY+yRMZyGyLyltHyr7777Esv2PEbHz/0zs8eY5S9Y2nXmFqjox+8Y/WD19z0+qcf+YkX7X7S2ZszdVMscKk0tLLcuF8AQhFjWfMnuj/xyn07x6u6yW1rQFKWWCeSFBEF8iVnTLCpRWHbSPncLPOLy7smZyICcR8poolIRjZCDoaSUrgXPCwLPIA4e6bDprxWBljrynpwdLm/dzMFZQcZiK+opDsb272j/fSLdgRgGbPMPYwcsiiNp5y45cDyn3xp8bytIzeu1udvzy969p4MrgphIFqAEQGSkgR6/oWTbBm5oe5umdRvXj33H162OjIxkokAcS8hhfow0ovcUw6iQQoQhDel9Ou4+cjKR66Z/dlPzNKtz5pse92/9UB525svePrZ414arGVl0FjKsluOLP3BDScmOkkRNM1PvGTPVJUH7m0z1iXWJYEkWkCCUlmUsm/byC+98IyffvfNabvRSp+55vhrnnfGaDK+Jaa4e+BsGX3ZM3YIuXJOBiTAxAYj5YgYb1c/cOHkh78wl3ZXdHTD4bVe451sxZUFlis8IrNOIygRQSTuYREmcY/MugRIIL4FmZPHICCAoHj0J6li0D64tvSmp0+/+vkXPO2sqbHcgHmEHCdAoMC5V4AQBoRcyCpt39TZucmfv3fi9DOn/uiXvzhZNbOAQEYEJ5WsDFZLmxRX3T1/69zmc2Y64E3UilZQSZw0EnWkxuOZZ40/afeZr33a1O9dvv/d1/YYG9k32t/eKSOj1e9fs/L7V930y9+z7Q0vOWMyMygyI7sXZeN+gZMUiiacqfyC86ehkWXCG6syiC8zShjrJiZGLj1z8i9vnT93U3W0X/oDB4IQ4h6KsChKlYsIIkryCLMGXGTCKJiBAdFqMeb9pRpaPVJYBQi5wiAI1gmIliUWVl9x4ZbdmyejFDPxAAovAhmUj964SJWKuqza33/RaadNjhQvQhGsC7EhQERgpB6ammq/eMY/ciDncZhf3L/Y3zw55hGJCBDrgogmOmS/aW75595386bKnA2CxrlzfnDjkdUvnRjQbbZNj23elK5f6rPYf/sbzn7ts3fm0utapx0FJARcd/NxFth1mt+4XL77iZMX7p3CB5UExtcXwmvlFv6d50+SMiV2j+h39vu/OLZy7o5xDzPxcASosqDLm548tXPLWAlPFnw9gQQ7to/TsULC+kfX+nWJToYIzCCCkyRz0gkiVWOq6tV+t+W//4aLXvHUzeO56ns98GwqCbQOQwowxNcICKjCKblAyvXayhLdgY2liGBdBCeb6tbU8WZ1clS/ftWJ9x5Y+5lnn/bqJ+/cNtl2Go9itDmJMsWom2K5yi+7eNt3XLD1H928eNn/vvNPruxy2vjpnXr7uLXTyFvee8dn93d/8QfPP3NT1W+qNmtiFIx1AUIRFJLsyGr9pL2bN3UqaBcpAwHifkFAgYns57fqv8SqxjEL67BO3E8iciFSYN5ggUy4IUglfHEQq91+v196a/3PHOixFrKRLcTsWn9hqcv0BEHIIMBYF4CMdfaEvZuMpghkPEAQBCY1PrjlzmUybUap4+XnbwGSJb6K2CBg0KHqtNITz5j6yF3Hxt2wkTtnyyV7wIPE/UqJSGb1/kH9G589jnM/CfMtHT1xIvdG27fU9dED/QvOmfmtNz/huRdMRVnr22gVtbxu8miKaLy59oiT1TJY4dXnT022rGksZ/GQZDRFiWj2bG6/6PzNH7392IVTIxxo5uZX2THJwyagkhjw9LM2ZbwEG8RD8E2jxkRrrXYSi65GCSJMEW5SIAgefZmTp4BAoTQeXgZ1V/WH/9FFL7lwc0RdvNuKglFQIDBJfH0BElIQqKSQC1oHF1aRR6SIQBsigpMpwnyA2XKJERs5fNz+6R8eftfVS//mxTufv29TJ7U8MHHyREg5LGeKe4xXevFFU88++4LLr1/9mQ/fcd3t9c4taWGwsG/b6Hu+OH909vPv+okn7dw0MqjHkjzxYEGKoPEnjGGtdiHMvVGVPZS4jysTRfRklYDwlEZYnB+sdmGcr6agToJULRRfXRrcemxl/4ne2vzq8eX62vn6AyeatUNr9Izct6nRZdOWMiDSwAGH5CiFIzaIdUlQ2DNdQRLOAwTrXMikQ0v+ufkBKS27M9q77ujKcil14xJfK4iilKN0bXT/EpiHjMFgYWUAtUgB4isqRWqogRaRsT7BBkEExWZP9GdrZyZdur39D1511sueMLV1qlO7QxtF9mZgbZVGKa30+Nixmk69Vrdp563bpgAPgiQekpMqSiFvnmieOOEfLQrLpN6B+T5gBIiHJ4xExLjVYMTArWV8HWKdraMp/Y5Z5otz3d5gQCtH4ApjnTgpMieNINywKpqmVL3U+8ibn/539016s1ZsLMmLMCyLiABFsE4RIUFIAQY4GOsi8EKCaGwAeW2pxl1minUeEYiTRoAk+q5OQF2WJ5M2TXU+c+v8S+9Y+WfP3vaWF5+xe8oalxlGBCYeXbIcQY6CFGZEGXgaHxn9nqeOPuP86Q986vY3fvAO2lMFzpnyT+4vb3rnne9847kjbZkLY4PYoMACGVWKaBRNwpCHKhE8QLDBMDdKqkgQNZEVAYSHJ8wLsoJCTZYfX80fv/rQh645+Ae3F5aWqRPRIQXtsqeTzp5pmTfHm6lD3m/HIGQoSQJBsE7ifiFElNFOGxQIxFcIQokIYLXn13abKdOh8MmJ9g+9+25qUOEhtYlVUlC1p9qp4KTOWrcBC2EQIO5RzBp36Yx29aILstm4k0QEGDFTNWduHt+xKe/ePX3OttHJdoamCZnMVAhhbWTmNXhT/JNzKxPyJYxR3zRi4FlOODIeQqhKUfdDHeXNmzJh7oUcB5caB5P41ngjS0BI4qEEqCDM3JuxZAcaUziY4ciCkydzkoSFgpyoN6k6Orfw39/0pL+7b4q6V3InE+AJQYBChA9MEagoKUIYQRCBo1IChVAyhfmaWbu4zS6JjBOBIJA4uQS4iRLWchvtR/9QKVNVtSlXv/KxO/7sjvn3/v1zLto1OShuCjMTjzoTkAABSi2xziNOG8tveMm55541/eK33brSXz3cnjxvc/nAVSfe9am73vjCc+qg4oFEgBneFJJJkMySAIkHSBASZMMjwJ0s3MxYF8jxUMjdrJFaV9yw9JPvvfnq24PR3u4xm5gcPVRssWkoorH9c739/QGT40w3k4NmpYgkvCYCklRMEMa9gnXhgUXdOOskHkykCAfEOuulZsR9qbCnZa3Ki5IIEA8WrBtAm2AFGm9aYbiMBvT/swcn8JredX33P9/f/7ru+6wzc2Y5M5OZSSY7JEDCvigIClpRS12wgrjTuuBG1Vp92lofqW1t1UfRVlSgxVakIhTR1lYNoCyCbEnYAskkZCbJ7HNmzpztvq7/7/ucmUlCgpnszPAq837zeazStCwuXLpl6mde8vjt45EJQlChylMRwZ1sQ9OIkwonDcDRAnYHUgyP1Z7xsnF6AnA0cqLgNGRbMaAAY5MNxtlTtNghHgaDoFJkAgg1YRCnUzBYUdxVVFoJJAESMskZ0XBGCBfoo53xyr75/vufteFbn7ieXOybcaiyibAF2JZXtRU3IpQICIMgKFAQ4B6qXTSGY5SxuGIyE4E5S2rTnqflZHl/bTtNkKMF1aMu29dNffqOlcf/1mf+xzef/8KrNjWuaRBnRUg2vbvnXDrz/ldcdfVvfjyXl/eNien89XfP/f2nHd80PY1B3IsNiLsYxN9lEDZ3MXczbtyvMGzJkP7kgwe/4TWfYnr0uK3Dg8uDPYc6hnrSbHP5tDZumDx/0/T5s5Pbp7V53djeUX75736iOU7xEm5AgA0Sn0+cnlRNQtgQoewUzUBju91RAhvEfStgxAnRzjXj+OgowoRIcw9OUchmmKONMRrGEAlxgo0r2SeyGkkhcZ9sJBRIaQuDajSAsBTcLxs5kewGjAKbtEE8VOIUc4oBcT/MSUassvkcY86UhjMksJVdIDT69q+6anrQ9BVLQUUBIWEb6sjRqi+Ryx7etHdx38HRkbmlhaVR0zRTa9rJSdZNTWxbO75hogxLoMALc13sGS3T0ts8KgyIh8Kwxf3tC+PQXTjOAfu4GuVSK27rPRvLK0v6B6/d9frvKN/+tA0t1RRxdkiQddQ3V10wfOO37HzJ735kdjC2aXzyY7u7T954ZPMTpxOCR5lAuLFLiQ/duvQNv3vdpjXDqTL82Hwy7n/7ovOeedn6i7dOzU4PJIQK4gRvXDgOhIQhAszDYiROkEzfo+mpmD/WLv3pP7zy4s2Ty7ULiQcgXAmt9Ll5zUB0gUyIu6jHFTVdjI08MO6xOEWoDQgSzAnivolVWelHlFgTLC3X4wvLMOVMN0XcjzQKEprFlSQoEtlvmBgLwCDOFoE5QxrOCKOq2MjK3nl99zNmr9oxkRhTau+CFeIEKWuljW6k4Qd2HX7Lez/5ax+b41BD9hTok2xogrXlK2fjivMmrty29nEXzTxlx3i1d89VIhIE5hEyAsydBOZeDOKexFa4vR/94gs3H56r/+E9Rxkc3TYc30/TZVPQnPux4fACr3zPGz+z2PsHn7VJYBBnR6HJXjT+ysdM7Dhv42ePLV4Wi6zEbYdGgPiCqGrCtav1v/z1HnK4ZsBNi37W5snf+a6LHrt9RqyqNr2xLdJWKSzVAmr6JQ/HWe7BPDwOZMhopDFG8924Bizk486L82fHYIwHJaGHAmU5cxACczdDgai40ypUQJxgAYkxQsaWxH0SUKPEjqnhniNHZybHGOn48gpMCxvE6RicKsVOmD+6ABSb2u1YP4A0Ib4kNHxhCcwJRhpzUss3PG5mzUB9pZTG6dDQzpTC2RONl6qGf/D+27/nt2+Cbs264fq1zigOKY3VK+Zqf82ees3NI+oczWd++Ombtm0777MHjzFoFkwCEg+JxQkGbCFnrSJEC5Z6KYgSCa4pyW3Q99HLiEEWX+b+hmMT/+rrzvvpr7tguSvPe/yBn/rfez6xa3HrVLekZk4NOXZs+eioGTvf3St+/xM71135wis20nV9G5ElBOKRq4YcuQzCaVQkTiNQbbt0Mz0+/k07h7/2vuMxNmBs+fBIFQoG8agykh1Rbju49OoPz5+/huO9CX75Wy+4YvuMsyaBSsitMyNca0jQhALFsMHuwSAeFivtLNa6yeHXTzRvPzpqojA3uuVIf/4so36lIUbRBNmCFeJeDAKjmk2jRH1DgLmn0pDgvqUWV2iDO4lVBsyqkDgdGYh22H7j7Myv7zqwppnmWHfkwH4eu9EIEoL7JmWfDhrmFke7jsFAziTHZtY2IIP4oiGjApE8+hq+gMS9eLkXawfbN05zgmypSCDRY4NBzdhf3DD/Pa+9btu66WyHc7W/zZEZpEEgTAlPT2jgGKili9947+34jmbNhAalz2SVzSqJh06sakvTytlqmezkSdzLfRIKJCfpjKiTDZ5ultZ6eMPx7pXPHX/lC86PHA2a8Rc+YdOVF0y99f13vPLP99PXbTF/R4RUlmt/pDA2LF/3R5/46Jqrrtq+tmYtYCEeBaqgwmi5i7EBPU3DaYyK2r4xTUZvB4ERVUVNYZV4tEkEAh04OuLI4mDz4NYFfe3WePzOjbgSJThFJlSrUUczgOXOHFkaDkqSSDwCFZxeN9ZePDvk5sUcb5mMj94y95zL19cYDDJLjlwGQhKfR9xJoVQ4qzAW4vNpVSABFuJugRAPwCL7XNOUqzaNWJoiR0zG//xM97XP6ppSwJxeVRvuxPC2A0fectPShePlE6N+w/a1W2eGIPHFQwhnUtSnAYlHUXCmFGt/xmCybFwzBo6QBDYnKIytgXxkxa+7ZjdlkO1wX11cyaanqWS1K6SoeOSYr3Eo2dd3B4tm189sXjftZuBMMDaPiMDUfqSYG/WUibXKCfqBHBLZlIwxjwZ0s7G4rawcWhzbtVxf/Q92/uKLL5sYeoVh0y8t9fWCtcMf/eqL/urll22baW/rx2dViFaO+VqmCuxvvv33brj10PFhaOQUj4asjlGVU4SW+9JweoKKpNqNVj41XylVUVkqM9MFMI8+4cwE5heXaVpoqN6yae1E9NUWn5MS9FbYCSsfuHme47UtDYhHICCiWKXBT75kPUnvZND8948eOrzYjTPqojQlGpR8Pp/EKmfJkTIjio24L+ZzzEMlMCdcevE6ptq5rl4wXX/3w8s333G0kaJWTi9Uigx+541LLIwGUTxqv//ycsHGycyUOIvM55FcqX0TrLJ5FAVnykCGeMpkzIwBAgOSgOQUAXsPL/3hTYc2TYzPjY7CIKOYCkICbIM5QWCRdt3fjw5B9isIEOKR8jLZCa7YMY1HNy/0Cx4MPZitPi9yI/3kilbq9N6VuLnGi66e/PPvvuD7v2rHUIOotQARpYm+r64rz758zV/+oyueftFw72Iz6+qiEhysOn+sfnx38zvv3LVkiqsxj1yUo0sZONqxcCn9iNNrk4wU5dZ9/j+f3n/+eFnug6m6eUMLGPNoE3dqmwZjEryytJKlEfdiYxWbIYuHl/WGv76VsbKUqCYEmIfFjjDBKj/lovUMbdcLh+U9Nyz+n+sPEkM7R24ia8jcg20JkNOSXAaQ4V6SFfxd4nPEQ2cVrZBXX7Dh+Rf5tuVaNUYu/vL/3rNERmnTnE72K5SxW4+MfvSa21kbHaIbffWTt4BQcFaJezOWCK0kqyQeRcGZ0pDU3DTRDttMI7SKk4RsTqoLSz2LHpSamoBGGokTJE4yn+NK6d0Ado1oMCcJCYmHzpw0GI4qQ0Y/8/d2/tWPP+Hnvuq8Z2xujobvIPZ0ccdKOTSm4Sb/P8+Zfc8/fsx/edmVz3/SNkUknaMIWcMmKZGmGdVy+db2P7/k0mdf0uxb8qxqpUIeSF0wsfCq966842MHmqbFnGIepkwD7712/y+9+ab5pZXSNGoHNulV2NjYGGzS9OQgmi7rb//VrdS2hm5Z0bN2jD3+/HVQQ+LRZmsVMD4o1ExnDPT7dyx99sBiRKlpGxtjgStRoAze9L49b//kygXTzZxPQIWHSxA4VKt18daJVz555pajmfbMzOAlb73p3bfMD8qoVde5pA0YbGwDaUkodHixe9uHb1khsAsWXwhSpVRPj+vHnncZRxlXt30qXvvB+d/43zeCQmTaxsbGxmBTM5u2XVpZ/vk/uo5D/SUT3jW/+E1P3PCUSzZCtTi7zD0Zsksz3nzitoWF0ZKkNIY0tnlkGr6AzEkCAWqpyyUkWqkIbANa5d5CDiiZQImafWmcGRnVELINBkNwglmlCoFU05A8YgJjevpooZ0Z5LMvmXnmxWtfsXj+7YeX9h3tVjqX0MY1g/PWj81Ot4MQkKaRUWtOEAjBsEABe/CY2eHrX/rYr/3Pn/zMbcsbBj4EneNIWeZ4/PRfHH78BVM71kxmImXFghAgkkQEBfHgDJrys/951/tuOvKyr9j6rMfNbl8zFAJBckLgiiQI5eHl8pq3f+o337N/45pmsgR7j/+jb3zspsmmT5rgUdfZbTWDunHNGFNNZ28d6LZD3Wv/7OZ//tLHjJeAHgQqWqFtuur/9p6DP/TW2xiLz66MJkqbGpA9BA+PgCKKTBt+6Vdd+qsf+nBhJZshS/Hs373+mu98zHMvG2+bHhpAgAABgpW+f/+uxX/+hx/fvDa+/ok7e3o7GxfEo8vQRzZ9ZMnnPX79S79iw+9/6OD5a6d3TNd/+ge7h1287PmXrB9LKJAgDCQqRbFvoXvVmz7+uvcvX7xBCyNR45++8PzJAcu9h0pKcPZUq3g0UjvEsUZMl8N9s328+60b6iv2LT9ux7hk4xBgp3urpRupDKIB8VA0nCFKIOgwUYRtPkdhWzLE1AQUNYpSl5I2nCmZUwIbAeYEcYIxSDxaJJxmlXqrsUPaNNlsmpxmR3KCoYDSrkmEQoAAcW82qyTbF89O/t5LL3/Gb9zQrCwNB5HdyrF+fPuUP3bd7W9+/9iPvmBnUQ+lQe7TYamklc4iIfFgiU2D9821b/9PNz7rkttf+JgNV12+7qrzxqcmmmhblGEtjer8wtJHb5r/j39z6zWfXtq6dnxty6f2+Xu/cvabnrEpDS58ATRKN6U32zZO/NzT1v78O45etCG3bFzzi+87snfhIy//mosu2TQ+Hpkajkb1Y/sX3/CXt7z+ugXa+iPP3vTOTx+7/uBoTdtRAfPIhLB5yo7J3/2mC1/+OzdddkHfDrqDC+1X/vrHf+KZs9/8lJlLNo+1Y8MmIk3f98fml9590+I1Hz3w+usXofzwjjVNXVaJkQokjzbBgMh2ZcXjk63/32+65Pd3zd86d3znusnts5M/9rY73vax/d/3nPOfeemmdePZNIVQP1rZv6D3ferQa/9q77tvO37ZpvGVyh0Huzf/0OVP3zFc6T0ASkJw9gQWqASMLt22YceW8d3H+03FaOln//AzP/8tl+6cnRjQjWrZfbTuWFNmpsZqNoVcFVF4KBrODNFjGh1ZzqU+xxtMiLsppHBCnrdh6nuesOn177nxkm3r5xeaQ8MkV8KAMDaWedTZrNIJIFbZgISAzJQSWcWcEBBO4YjC6UkCbCOR+fTtzRtedN53vuGz29r+thiUysEcae34r187/y1PmZ9dM9FBU2KsDUFmRYQCg3iQ1M1T2wsHK1t2rnvv0cX3/sVertlHW9gy/i0b2jHqEcefHuzY15HJoF65Yc1c131qz9x3PGPDv/62x6wpTV+rm8I9CAiVEIHEgyQJqQQEpzgjWqh9lMG3PX/nz//t9bf13ayPbJtqXnf94us+dP1jL5y6auP4fPpP9yxwuGO4Qo2ffMqmH3r+he+64To0GNATrRB/hwRSEYQkHozM+h3P3jR/fPmVb759x9bhhZH9oP7yew788jsPsInnbVm7bawc6f3eQwtHbl8E0fRP25gfuK09cHy8RiNTSAlTwJwSFAlJPCJWBKXxysjl4pnBJ3/k6mf+5kduOTi6ZKq/cnbsmr1c8/pdDG956rbmwk1rah+fnFv+xK1z9C2T8fgN5fpF2Hv0TT92xTc/9bxRdaNUOInC50gQhEQIcZ8kEEUiEA+KJKQ2nMG8uKcAVAJcvX26/fGnb/6J/3rTxvMnRm2+/eZ8+6uu/fLL1l40XXb3g3e8f8+ef/fEmalhJRoyIniIGr7wBNgpCO2aWzlyfGX92DgGcRcFNqRZM2z+5YvPa1n+7b85TnPH1mZDVXtUtTfGyCDuJDCPComTbLPKTicgTsgIicYVkhMKyBEJgcRp2dZJgInK4MVP2fDJW4/+m3cc2LLG+8O191jLLXfMfe9rb9y4bnKsWb5odvjUC9ddMTt2/oY1uMtsMkrwwCRWDTZtYHD73x5M8ihr1j5+Q6dY7qyjR46/+YBQoHpR46l1zVKWzxxZ/PiyGM/fesnl3/q8C6aHsVJHjbPJJIJVBmGbLked6Fxr8sAk3FfTZd8lI8sGFIW6WGiXXR+zZfi+f3zBM3/n9t0Lhy9YO/O46eVa4o6DC5/ce4ySlw2aW9t2ean9gasmf+bbHqPsrluE2i3TMCJt7skgskKXfS9W0uYBSeprNqX9oa+7YOP04Dv+4BZUGC9PWCdYOdI379h1hNEKTXv++Nj2mamFlWO7RuUD+6afeUX5ka/b0aMmXcKpABuJVWLkvqt0WavFw+bEUQdNWexpu9RjtrTX/sTTf/NPbvyld87R1K2TsWVjs0y99gh/e/s+VGYHwytnJqNfvn6pu35fe/mFk695+eVffuXazGzdqXjEGLjwOU4zyr5PunSaz2Mhu5rOfVcZpW0eBNt0XlGu9EnPPRlBFGeqLeRLn7Plddcf/PinDl42O9w8Nukcvu+2Y+92uazA5BRtC9Fk51JsS+KhaPjCMyfZ08W3z3dHF1bYOJauIkLFWICNAshad64b/tJ3XvX1zzjyxg/ufuNHDrGo8cmyZSwOm5XE6ovbilllIfOoso1XcTeBABUTRiAZsJwoQJyO5KwghaRcNdYOv+3Z2//Nhw9SaRpZw2U8HvEXtx5j9wIO+mN0BzftGPz0M2dfePW2yzeVJkfJIAQY0hRxHyRhP+vi6d3/4SnXfGLhQ5+67WN7R9fc0XN4xETLwLAMhdru6k1dYUO8+Mp1X3n5+hdesWHH9jW4c18j2q4QkSJYJVaVpmFdO76mRQwmxiA4DRswkDA9LmYGsW6CTVlLAOFKiV7tmBf72j7jyq03/rO1v/a/bn71R+c4ukg7oACiaz/N6EmXTPz0s3d8w9M2jw/y9nldPFMOlRy2Q0b9oBgQGLNKVNRMwswgpgaQKgHIiQLEfcoaQbUG8LLnnv+0x86+8T03/quPLFy3Zx63DE0TaIqllVuPHkPigg0v3978wyfPPOPKTVPDJrNTDGvtMkpLQkJByYYm1o0TOTbZVMQqg3ioCrUjpLG2Ro2Vms356wb/9iWX//2nzr/p3be8etfiHbcZicEyZQzn/oX5/cuVTetfsjO+/mnrX/jE89ZNjqVrVS2l2I29NFBLNNxFg8Km8cGaASs9w5bPowRpXKxvWTekZjQFEIkDidNQKaxrhm0cybxqUtzNTgQqVKtUN1sm9X/+0RX/4i27X/fhOY4dYWKIguw+XStKggRRe9qQeYhkmwdiLHR0pfuR/3rj733k4Lpx5iweGhXY3Pj2/Uv/7fuveOnTN65kCWhTXRMNAgQYnJkRZYQ017cfu/XoNdfd8XPv/iz7Jlg32DZVu2znXPu62EZ0bpJV5k7ikQnYLm49Xt/z449/1uXre2eDkHjobNI1yFQxll0UVfkHH5x72R/dNLW83DVNlXzSBCpYaCCNF322T44k57evecHmlz15+3jb1qymp6ihSIX7YpATCTSC/UeWDsyP9h9fOjinfYePHu1T0cxODLZOaeva4fia9vzZdTOtoHYZTUjct/nl7tD8cpRBrf1wUDavGSviPqUxqbpSY3jb/ErtskTTZb9hcrB+3LhBwV367JtgxeWm24/tO7B87f6F4wujpimzM2M7Z9srt81snhxgpXMlR4ePdisaGrf06yebyeGQ7BXFNtBZ+w4fSzWdmqz97NRg7XjBlgLE/TKIVTa69cjyHQeOHjjcffrA0nznJlg3NZxdO7hozWBmZuL8jW0bYVJuEKcYcMpdVTu3Uo8dX3YZZuZE1PVTzVg7APFosJFYVeHm/ccPHVq4+eDohrmVyAyzaf2aC2e0ad3wgtnJmWELmWmdEPwdBsHB+ZW5lQypZDc+XjZNTYi72ZlVZd/hYz2lj6b2/YbJdmailVMKEPfNx1eWjhzPTkOojUcb1k6NBUWupkThHrrMNrySumH3sRtvO/7xg4tYa4ftjg3tJVuGF2/d0CqboJomCg+RbPNAjIWOrnQ/8l9v/L2PHFw3zpzFQxTW2pYjhxZf/KTNr/m+J6wZmBwVSkaDMxSAMYbEJbNfaRSU4ZJ18/7lv7z+9l977+037V7Bzba140uD/ljtMhuTRpxgEI9MwHZx6/H6nh9//LMuX1+dBSHxcNjZOQYJmEY5X/U7f3nLT7xtVzs24ch0SmEbG3G3gImINSpL1YeOHf/B51/wC19/8Ybx5ZEnwANV1HIaaUNiHKVgqFBAlVUZNirilARnTUdJ1EqcljlBnJAgEPfFrDK2qEhgTmgMfbqJEHeynbUSxcpGBQxKTggMwn3vvsbYoFZRKS0nCDDGCZKi+gRcmxJQIUCQTmU0AeJByaxBEgUCSKoogLhbddaqxqiVuJszSYhMR4nAnBBAdRYFjx4DBlkkJ3iEBIUiLAROlH0NhWRLIXFaBnGnHgqIk4yrTdamBCQIBElSow0Q9804oSAwJERNgqogsygkPierKz3RtxpjlZWACBLoU0UJVFOiiIem4UyxdKyrW9dP/+GHD77kqXu/8Smbuqx9M2ydkSPHGBiQRGSl1GYCk1nH3F2xefDYzRe9+KnbPnzH0be8//bX/s0hjg22rRvvGx+ovezEIL7IpMJQciToid/48z0/+7YDO9cM96RrVhTY5hSLEwyJFmpdLC4xuHD9uv90zf5h1H/9oksm2t5VRMv9ELIUxn3vkjSNe3CJppqUwq701V1ko9JSStglO8qA07Bda08UIHBEw2mIxH3VIK2SfWcpSulH0ZRGwkbiFKmWGFDJ2iuRwjIS2O4EUSJLU0n1qMWWexNJNLIkE2lCIm3aPp2EQSIcQUZWRYB4ECRZkVnTvXAIiUQG2+kqFdE0NiRquIudoeiJCCtHPQ2SskNyFB5VAoRNdRjk2qhCBBXXXqo0A9WmBMgg7k9mtXEIkFUE4hShkjZtn07CICFHISOrFEjcJws73VtpNYKiRGS1AnEvGVlo5LbPCtXRhFAqzaqiKmRTomAQD0nDmWNc51UY7//FH3/60p0bH7dxrKsrMMxowiSWZLAEOUjLadWMxs7ibsuaeOHatV9xycx3P2vhde/+zOs/sITHdqyp+1RGFlmRQHzRkIqNnC5jf/yRvT/7J7dfNOXbUpgm3FnGrJIgzJ0MhCOr3e0hLpqu/987juxcu/eHX7BVgSG4b8aZWaKkLTsi5ZSjRuAMpxUGO6RhqISpZOeMEg2nJ0XTOisSKtwfmUbOAEc7yF7Z16ZNZCgSdxG0mX2YUkSjtOVwmsxoGltdRQWyaigs2xqACylkR9oRYNeIsAtdI8hqAhWQHVgSD4YR1aIEihBkkhgUFmIgHHJmSoh7iKY6C2lX0yBA0EhJdkQL4lFmkYGI6C2cikDFTjGCJm2wQrhCw+lEwYgqg4TEXQw1InC4b2RcbaEGZAsk7ptEIVOghhNsC0cUfAKSuIsIG0iEFcUETrkqgIJQAM6MCB6i4MwxUY7XOjvefny/X/VHN+6a69pS06OOwJ2gYiDsYktBtH2MoSIVaGuW5Szjjb780rW/9u1PvebHHvOKJ3a7D2ljVzepJwZhcYKFsZE4i6zImpii6w6sfPNbb5wc+qBHffbV7tyCuU82REZBJbu8uZSLx/zjf7b//bcsh7pqTkeoRLEBKUJWIYhAIQXRQAlFo2gplHRkEQNF44bTE5IpUYoiuD9GKEIquLhKxaWFCFGownyOFSq0xU3BEQ60KtQEChU3Td/YTTbKYkeERJFCgkBESCC72AJpYAZZxmsMKw0qEhIPluQSLlLBShRBCUWIRhFByBKU1tFyD2ZVCEtBlAINjpAUEQXEo06hKFJIKlEiGimsaKIZxACFIhRhpxTcH4VUVCJC3Ivs4pQJtWaQMV5jrNKgIon7ZQUqQo1dwATICJDEPRQrhMNFtIQiQIEaq7GkYgspQjx0DWeKoSLM/hxuWac3fXDPnqNz//G7nvCEzTJeUdM6Q3YaQhGc1HKKHApn61oNzskSz3vM7FUXr3vi4469/E23MDp03lS5owoZuygsqhPE2SJqhZKV8j8/sIfblzeuH+zOJlllMPdi7iawsSq1NFIX81E5fuy177r9idvOH28xiPsmkDhFCkDQABIgTpKAIDhFPCBJPAjiFKHCSYIiQKjhXoSKOEUgCSiAOCEgCAgEYlVwSiDEKSKKuJNAEIA4QeJBC1aJO4lVEncJQAEEny8AAUUgQAUQqwSFLwCxSohVAUhAIE4Sd5IK9ys4RSCJe9EJnCQQBCBOkLhfQuIkFSDEnRR8nkCoUBCrBCgAiVMkThIPXXDmOffWumVm7D03L33Da6598wcPLo08jCpcHbUabPDnYBsbCDVyYxcUy7Vb15bv/bKZD/2TC7/msvNuP1a3NZUojQauODjrXJqBfMtc/uxHDq+bijuykSVACebBSCMfhm1j9XXXz3109yKrzDnnnHM/grNB9v7q9VNTtx7Ui1993c+/6VPX7u0oTRujpjiNnWAw2E67SpZCKkWxCjwoqimnn7Rz3eu/7/LveuLMnkMr2xv3WRWRaSTOJtsV9MEbj7C3m2oHI5OSWSUeHGOrKJc9mGCp/tWNi5xzzjkPJDgLDEHG0VyaGqs7tk79yl8fuPrXrvuVP/vsR+7oVqItJUJpp22wpJDAgI1kyaEil1JZdTxj61T5hRdf8rVP3rLn0PzGsehJWZxlKpCUG/YcoV+sBLJZJQgI7ofNnRTueo2NbNx9/LNz86MqYc4555zTCs4GQzZh98ft3TW3rIvJ+dFPvvmzT/p37/+Ft3z6I7uPHe8V0UTYmb1r7z5tp+UOBDKWFG1IzaSUyY6ZiV/55stZP3l0MZsIBIi7SOLMsokoS33uO9IRqgInGAEGcz8EGJzCpChL1thAv7d3af/RJcA2/zczpHHiaqedOME2Ts4554EEZ4HAuM8YYnDsc/Tj3rJxYn1M/uLbdz3p33/4p974mT/76G275/osbRvqFX1NnDVakM3dJCQUJWu9bPPgV5+3vTu8PKsuSNLcxTZnljCw2HWHjq2gNl15OJyEM6tYE9CVrk/+b5fGFs5wHx6JJeWKqKYac845D6ThrBGYE2wzimZ/HTVFW2c3Zr/yW++67bfe2V510Z7v/7LzXvCELZesb2i6jnCtJYK/QzgVhe6rr1zLlsm50cKgHV+ScAVxJ3NGGUiz3IOwQeJhkCCcXQEybP6vJwxKSnWYk0SxinD2Euecc/+Cs8+hhs7O2nu0N48fLrFh/cT2mebaff0PveGGJ//KB37rHbfdcGAU5EA1zX2RwGb7punvuGxmcTnGo3CWyWgQmh4r2CHx8Dgho7TLiOhLCR4lNjY2NjZfPCTV2hX6QdRh9EP1Q7lx576XGu7NNmaVzTnnnNJwttjcJeloJTWZRNYufNh945wctuvGBrctdD/4X3axqfzqC2a/88suWT+pzJQEBnEPaaYGzZN2jP3e+3Ks9lIYcbZIwOSgbJ4Zpx4vanDlFJtVEg9MuFeoIY70PHltMzkxBgjx0NkWGAyhVdybbQwCJECcHXZGaL4vu+6YW8kmpZKjnVvWbBhv5B4a7mIjiZMkMIhzzmk4Y2zuRUjcySSmgizhtNWrdM4Fl8mmzGwdLXfDV/72zbv2j171rVdMD/paS4RF4S4SciO4dGMhUQRZQWDOjnTWQTTbtw6ACJU+U4qIBPMg2AiiKRmTOZq3nr99cN50ABIPzJg0GdbIAgZhJIGI5eT44mhp1KNGYtiwbrJtJXFCrSs97ZBMmWiDMywiyspSd/XrP8NcTzEj//WPXfnlF89UomTvyI5BWzuV9pYD83/ykf0rlBc+dvryHRsiR50aSwP3qOWcL0kNZ4zEvYi7GcRJNidJ5hQvVZbSgyYvu2TNq99x49dfveGrHzezohhXZ0ogwCeRKFi3dprxobMXMmeNiSQDnnfJRsZ3uS9EwbnKEg9ak+5Vm2xQPu3y9SJsJB6EUTXyoNfSQIUYLHbefej4tbuPf+bmuQOHlz573LuO9wslRtlfNj5x5drB1o3tky+eunrH5MzM5DCys/peY6qocEYJKLAz4pC8SblLERgwqgq5RlYVbjpw/JL/8An2r9D6JzX4q5+8/NmXrim1ZpRKBIhzvhQ1nDUG8SBkNNF3ffTHKbSz195w9KuumG5iGE4DwjarJGSoY4MGVVIKcVZJhv7i2envvGrrG/5mbtMaDjsyk1USNg9ECNU1lD0uV23RMy+c4kFLDXBfqYMYP76y8q5P7v+jv933+uuOMDKRyAzHp9tm2I+C/i+PrfzlrT0jE4W14z/1lPXf8bQtV14w3ba1JkWFM86QsCCtE4i7SSIllLTv+sRuDi9cuWXQJZ+e7976N7c+6eInTCiCHmQQ53wpajgr7LAQpyT3r6e0Tq8Eq3YdHI1qjMvpEsLcSVBRIDlRWAKDOEsEoVKrp4Z6yVO2vuG9B2ZoDkJEpNM2iNMR2IKwq9hoH10a/dRzd2xdO54mxIOhtNCg+EM3zb3qT2/9H9cdZNBcsKZZt6Zeu9ywDIsL8875aIkxqinNpWs11jDX69//2f5//9d7/83zN3/Xc3duXTNmI3HmJaSdBnOKIOyRVYRhuSYKxxAZL6erVwXGskVBnPMlqOGMsQUGgVSEkTEQYUOmAgxGwkJgwFIlx2rgtie6Zmy6jwHUzm5FAJJPwoCWukqtiqGdnCAwZ5yxgSh299zLpl/5/PN+9S/2XTBTPttXVMBgPkcIbE4wNjRyOmKTddPIX/v49S+4erOxnCg4DVOFTNhEuK/6b++447v+4EaGcfkGZcRnjtXPLvlrLm2ftmVs7Xk7N08xiFzqdcu+uWOHFn5ld2HPPOviis3lWD/4mbcc+p3rj/yP77768dvGM5GcUuGsU5SW2hX6r3jsViYOfOLAPIxg4pufvnOqOGunEqwS53xpajgzjFbZQAE51tPTxJFaO1sBNtGQRK2ONAZJQECxRNS14vBS96QLp6eLV2oM6KsIPidk0L7Fjq4Tg6SBnrNESCmTVjM20M98zfZdh1bedu3cRRu0aykUI1NYZSORKckCA2pKuB/Vdt1WVpaWR2yc/FffuGN2OFjusm1rITiN6tqY3q2DUR+/9NYbfuHtt164ZbKP/sbRsB7rv+uZ67/vmbOXnb9u89SAe9m+4nzF3qMf3bX0qnft+8jNx85fz8VbfdM+P+HVH/rQDz7uSRes6ftEUBrOJqNogNICV24dfOKfXnbNtUcXuvK1Txh7/M4NQBROEOd8yWo4M4SFJEvU2mlx30Iw6jZtnFTp5zuqxrIup+QGLFm2MatE0zRHZ8vg5oMtW9Z/2eO2QtpFTRuIkyTZzlAwOrD3MHWQ6nGF4CySpXBmmk1rx3/5Wy/86OHrd93RzowtHnWaIoE4oWCnCCTAySDYqKO7F83Umnd++4VP2zpZs7bq8ATiNKxUR0v0A/Orf3bLL/zxrZdeMDPfLe9dNJO85RWPeeHjZoZtATJTCjBglJlD6oVbZy7aOvNVT5x+3Z/f9k/+14Etk/0Fk+1nF3nyaz59449ecvGWmToaUQqIs0bcQ4XHnrf28vPWJWqoNbNEcM6XvODMMOGQvTH7/mj91a+57K9/8uofeM7mA4v9/r390lLd6JWtJWajmYmJyWiHRcOmTDYxU7y9qRvq5J6940zVt3/fJZetb7KrbSMbYe5kUMiLtfn4bUuU0mFxijnBPHTmkZGAiJBIs3PDxDt/8OoffsbYEdqJaAopLAisEwg8EBulnVbnyd1z8aLL173nH1/8nEums6qXVJrCaaWVBCy1ij/+4J5/9t/3XLJt+ki/snfZTI9f98OXf+MTZwdNdNV9HUmW0Ekhilyh77uu9tMT46980eVve/kVexfbxY6dY5Vj/b/8/V1Hlkc5GDr54iFnXxsM9FlbSZxzDjScGRJOYLwJ0BUb2y+/eN2TL5z6nufM/6+PHnnLdXPX7VmgS5qeOMZgnCi4X8mk5uFR0PY/+NzZH/h7Vzxhg6l9bcZLdkhYYCQjcBB7jqy8+tPHB1OxEI2zA7NKySqLh0isEg9X2gKtQpDZ9zvXN//k7130Gzd+qJtrxgZ1KbErxIwllb7vj9XuQPqAXTZO//ILLnzZczbPTix11ZIHqHMzkEHcl5ArtZR21/7jL3rr3vHZ6aM5OtgtMLX+Yz9w4ZXb1tdu5KZRido7kLibq7JTU1QH2Y2ygfz7Txl/42jnS173meEmLlobv//J5ee969bv/ZpLhEF8cZBMGZFF2WTUEFA450tewxeQuZPAWRSZXYqxZmJCwBh+2oUzT7pw5rufu/DJOxZ271++5WC/++DCvqOj/Yv9SgzOnx5etH7sqh3t43Zuunrn1GTps8cRgBSS7NpZxRlQFUF9/w1zHFie3TB+W28MAgzCPBgGZGwhICGwyCRAApHYSJziAExKJBYhxOcoVYuD/789eAHU/K7rO//+fH///3M595kz91su5B4IFxFCBAFXKrUWSpWi20Vot25rK1RXq7ut2tW6tba6rXXtKrrWtbayFtHVYkQol4pA5BJCAgkQZjKZ+/3MmXPOc57n///9PnvOJJHQZkwmZCJJntfLFGWHWqoP3XOKU3njZD6Ra0pxTPZYObUKdc10Z+NE/PXLNr3k8vqFV01fvXkKPPJ0CiWPIFURBvHIDEkujv/rA4c5sbppPhevsjL1ke+67Mbd8012lSrhDB0sg3iIEnVFxlHUr4HSNG3v9bfsuHvfiR//kHdOLu6c637Xrcduee7WG7bN5FwiYUI2UjHhggI5I0xy46hFloXDKjiKrUCcJ0QpJSGHbIfE4yCnZDU4QkIUETxMKRaSXCCMs5QwUFBFwS5CdrGKIgCjNWQpiilScpGCCysgLJdWEVbYFsUUqKCIhKC1sKugWCFnMKoYuzQqLh0ZjIN1xtSKYQFyf7oPZKcoTsFlGyYu2zDBDYzslXbUjFht1Tomas90S6p6HcCNi0ooUIUhQFIRlEKDulGOreSfu+04HZ9xkQIwa4R5bGSMIIVsQHYRKiFk4VKySovCTiiUC8UOsCwJSfwpE5RMyYRDLqkOfep4853v2qtOdaZZzZpQWpwv9amq+1tv3vY1V26PXCb6MVGr36kBU7A7EmvUAYI/i01E9+79p376fYf3bO5F1oFF/8w3b7v5hs2ljGpqIoAEVDVfTgISEFDAYk3C3/7qK3/84x8fxfSEVllqf/+249e9dgq7WGCD3NgyDhdIVRlmVcUoj3DVyDm1PYRyQiDArCnL2R2yyK2pCKnicVCR2pokWmOrguAhXiNkS+CskolKFEqjSCMnWVJbRScpJxrWqILSZIMlKw9KdEMhHlkpNm0EIyeVEgmEUJITBaqEMgwzlVRHgYw9UsiuGbtUKi4hYYFArItwOZs9Od2Z7ddgRIQwbSnZTnIn1KkrqoTEOuNSXIqLsKIKIx5kG6JyO4pUucnu/OaH7v/YPae2z00cd+MSiIslzitFGBAGZ0XlJjCpCqqKAsEao4IxCoXDDQiC8yybknJqkim5Vjq0Un7kHXeymOcn64W2H6meSz611LzxOVu++QWX9eTiFqUwrTN2ipDClsRjEawpv/vJ05SO7PtGzdTmuTe8fAs0dnJkUfEYGJArymjk6+en/s9X7fqedx69cmt/enb1H9x2/E2v2LZ5dqpxqcuoiS6kWu1KSaEI5xJ1lKKok9tWuY4657y43Nx3qjm+vEJEr5Ou3jo5OxGTqS05NdRSsRKPj7XqThgpZegqI/5UJlVllPHAnUTJ6lRGBvWT26RC1Muro2NnB/ef9XJbitvt8xM75robu1rjtsnRQxIXFs5FZDopgKXV1YWB9p1YGTYZs3m22jlXTfbTRNVzaUpJJeqaYZXt1GXskqm4dCweRqYmDfLwBbPd6W6wzqWUiEiBsCw7sAtgy41VFaXkHCGoAEnYPMQutpJHKcXvfOr4W3/z81s2zJ/0qFgIEBdPQEqdTg0uppKSbNVnGp840y4unR3mXKWYm+xunZuc6LpCQescJbpC4ksyKaQqryilJaqfu/Vz/+lTZ3Zumj80HKYaNcsTnjxF77u+fktPtG2bIheX1nVKoMAyawzi0RgknVpqfv/O0/QICkP/0/9ufudc37k1VRYVj0mAXUy0Vd2Br7txO+8+vbQy2NDrnzu5+qmDo1fNUmxEgPCq03/4wP6PHRzO97hnKf3QSze8+NqNLm1KvT+55+jvfOLUT91ztiyazLpgvlr51ufu+Y6bt7702tmu86hUKQoKLoaNxPFzo5+49cBks9JStVX991+15/L5ZCOxRjYR955o/tmtd89WqVXZUI+++5uu3zZpojq1zPs+feQXP3r8P99/BleMRApY2TXfe+vNO7/1RZuu3DjptlFUiAtxicqKpAOnl/7grhO/+vGzH95/AiYpQEHQj793zexrXzD3whu3begot86pmxjhghJjl0bFJSfWCVOlRJO3TPf7yYAshQq2JBLCBhQYYSepJAokW8YCCSRsg01xTpFDnT/8/OLr3n5PTE4OPSzYqiorC2wumnmQ61QN2nLf0aU/+vyp93zh3KdP8PmFISnRtpum/JKd0y/dPvGK58xftbWzsZ9yaUO1eJBQ2COVDvVCqX/xgwd+6oPHd2yYOjpY7vTcjrxL2r/a/otv3njzZVOjPErUpiaQjQWyURgM4tHYlvS5gysfOj66op/NNOXkK1+wEbyqTrc0ouYxcjG1cO1RW6rrdk7+xR1x69HOFWWF4COfPfGqG2eqQkmdRFNwQ/rsF06/7YPn6h2d5u6V775xEtLpUfnXv7/3x2/dT39iV1WfqQabujGb4gzVgXbmbR858rb3HfuJv7rh+/7y9RNqGlMruDgGrTbl5z58mNEI+tT5b75iJ2AQ55VCeHGl/dX3HWeqSzNkQ/3mV5SY5qP7z/69f/+FT+5b2T6VNkVVS9NdV1GO5P7BRX7w7ff+4AcOffC7bvz6Z03nXEyIR2CTIg9J/98f3/eG3zvCkRXme1dOzKZ2tFrKhKxgwf2fv/3sz3/o4Lc///j3fuu1L97ZLfYoOh3GLqGKJ0koovKIVptnHalyblBdrAR2i4qoTBQjkAyBJdsCLMm4lIxkSaUJqFJazfG7nzj0hv+wD2K2bheLSIGVKTYXyaxxQJWiAJ84ufLO9x34px89yeqIKqF2vk5Vqybqk4vl906d+L07E+/e9403zv3EX77qxdsnwY2pNRq5U5FLcSfVgxJvu/Xz/8u7ju2Y9KlCTtlt3sjc/tHq7qvrv/6yzXVSySkqMhYEIAESRjw2Yt29hxY4s9Kdm7pnsXnt1RvmZzugmqyqEo+VFCHAtQGlKn/DdRtu3X8qdU3S3UfOnWs0XZNdCiGl2iV6XTYuPq/Px7ZU/W67Svlf/9+7fumPzu2Z7d1/+tzBjTWdznIDx5eZ7F0+6eWp3vyG8sO/dWxUej/8uisSLdRcvMBM1Ff3qoE5GHXtlnUGsSYSxIQKs+mGqXJ4SDXZ7ffj0/ubl/zM3Qg6HFkMNgSJI4OWlVZTne111dm2cf/qwst/9o6P/P3n3fysmWxCGOQCMlZpm6g74uxw5X/7zS/8qz9cndyiq3alO1Zi7+FlZrpMdigNZ0Bnrpqr0vTs2+9ZfPvP3/XRv33diy+bSKVBgoqxS6PiSWK1q3W3S86Xbe5NVQEOt7mUVpEdiU4IUYKCohhhoAiMJNvFBlJbHI5UNUX7ji7+uz8+9hO3HujO0E/9M7lOkW3AFpiLZTCitI1GA/TPfvv2d9zWXrWhszzZXcVDtCjZktt+pU5d9cgTZfq9dzbv3fuZn3v1tu96+Y6oOqulU7m1c131ji41//r9B3/yPx3ZNZtO5jK0I3W77bl+d8So/aVXXr99arKUrBRA4jzxp8Qa8WgMkkaFjx4dMN3LFsuDr9uzeetUv5Q2CAzisRNrhCobUT1/9zQr96eNE73Kbz+1+r8vjKY398WoqKqw0MhB1qoTWStt/OLv7v+l955kY2frrur/eP1Vl2/d2Klt5yOnVt/5qZNv+/DJnXP5i65v2Dn947/5hZdfM/cNN262LYmLZIS1UsqKG6JnvowwyBJOg1YLo/SyLrcfWP7Rt3+WnKn8o6/Y8srr5mdm+ymqpeHg/oNn/u77zh05cXbH1GBHr3t4he/59Tv/4AdeuGmya7CLEDalzanulOFS4Xv//f5fff/S9bvTYus7jvdedt3k3/0rW6/Z2e9PTAxynD279O67z/3UB491e+XKqWbvEjf/4qf3ff8LLp/vtVbF2KVScckZBHbdWWphIj6z78z7P9PbtWl6dq6/uRuCKhlaEAgoAgcUCeGiEAiHBHJoeTjce/D0b99x6sf+y2kW886N/TN0F9plBSYZs8Y8DgJsTGqji7pNn8lyhpUFqyjswIBBjRnYQ/t4lednVyfy6C3vyAcX2n/4LbtmOkFEpvr4kZWffOfd7/z06s6NE0eb3JKVRmqqrZ25+1YWf/Z11/2FGzaU0tgpMIjHxTZrpKZpPnJ4QK9Lm1Fs2TIV0BpSJLcUEzUXybakTTMJZxdtr73vTFkZDKFvEgaxRhg4kwvz+Sc/ePyzpysm0i9/y47XvezKjf2AAXRAN+2ZfcXztt1y7bE3v/2erT0fLWbnzL+69YsvuWpDv1vZSFw0c57A/NfEGgO2Qc3Cav8HfuvAPUdXXrJt9qfeeN2LnjXTZQQFBJu+7lnzr3ze4Md+84u/cMfx7b3qmgl9Yv/K++88+fqbdzmPUgoT2FJgk6pfvfXeX33f8nN2l8NNObUU//7btn3Ly3bNTHTBUEDsnv76Z2//lpumX/Yrx/e2XDUxuvd051feve9HvuP6SoxdOhWXjgzGAQZU8mLJk/349c8s/vonFtmob71s6pZdvWt3bL5s28TMpCZ7da+uIkUFoYJVXCxn5+GQ5RGLo3zq7OCu+5Y+cO/yb9x5ipVRNdPfNFedaFdHlSNQIQvEV8SmrtuqznbT65BPWsmWi5FYJx6yGp26PXuamWU6V081P/Xes5NV8/2vvX5xqf2Pnzz21lv3cy5vn62ON0MsUjfy4mUp9i7nt96y52993TalUVOANtHhcbHNOgGlLZ86tkIVw1KoYuPGaXCEsoFA5uJJAupujy0TiyPP1cHx1WbQAgVCPIzbElW39yeHllYG+r/feMWbX3ZFkIetkyYCj8gq7la86Zbti+cGb33H/Ts2dHaEf2/v8t7jyzfunuUSEWsy0eumu5cG7fLqNRunf+XvXHfdthnnUUPKiqI28pBSbZvt/Oh3XPvFk8vvOdKGMpP85u2nX/O1OzuRbIOLQnYV5RP3Lb7lXQuX7/ZC7pxajt94485vv2ULdEpuWyRZHmFQeum1m9//Zr3y5+89F9VVs6v/5EPtt7/07A17NhQ7JMYugYpLziDWlOJ6YjkPZibK7ETVjPJvfWb5tz55Dh1hOjHTedVM96rZastE1enXkoLIaOQ8WG1PLDafOzH48HJmcchKptfdPhllorNU2uOFElXkVVSXqHHBIB43CXLpBMml5AqDtQ4jXIzEQ6pS2jQTpc1N3Nurd04v/Oj7h4dH+/cfOnXrZ5Zn51I9xZGmhKmikdkTs3uXhm96cf+HX7un341cSuUKFSgQXDxJgFmXc6FUSsMmRKhfGaSSUyijSsHjNdHr7Jns3H+2bKxaSoRYYxuEeIhC7Raqw8v+gZfPvelle2TnEl3lHDbRLR6kqilNnZpvv2XXP/zg4cOj4ZUETfeje8/euHvWWIhLQiK7VNsjDuTB//OdN1y3bXrYtHUVIjpYjpZI0ay0bJ/qvuUVO9/za/elySBVH9179sTCyo75SUqWkG1ptZR/84eHSLmmuW+Bf/wN295wy44Vl75blGqM1KoWLlbTppdfv+mHX3H2J95zbHpzoln8nbsWb9izIRBjl0bFpWOBeEgJyEOUFrPOQaeq5jupP00p1SCXswvte06M3tMai7ZQjAAhSIVUU6WJDlP9lCarEXE8l+wCgkCYrlmTEY+LQSDWhCk5FTmkXFBVINvYrBFgHpKFcylRSidT6qPubK7yL7z3i3SqXRvS2cxJE8nCmbjc2rfQfNtLt/3kGy7f3FO2UtSscYB4XOwCcslK1eFzQ5rhXKpFISwLcNQhia+MlFIhZ1IFI9lQhIX4ck0p9No3vXJXImU7JUFKBomoJpCjAs1P64deuOVH3n28O99S2mNHB5CzBVmWlcQTy1jTwYHl/LdftO0F1063mW5dgQOBUKeWUdU1a15y/SY6X1x1d3vtgyPvOzXYNT9pnAnT1FHdvm/wK7efvHKmc6p0mPEbv3GXiG5uSREOZKC2HRFQwqL6a1+z4Sf+8FjOZiJ94Paj3/eqXf06MXZpVDxZTLDGBhkacybnMxikiJTod1IPOlgIxBrJYOXWabVo5HwKcua8wCCzxpivjMB8SagYg2UwEuYR2SDbIZBzkU7B/Gy3sQ/ZjtR1GpaVmehvzvHFUX7LN2z80dfs2tTtlExKPEji8ZJUiiXW5JxR5FwkU4zEOgHiK5GT1AoEAsKsCZHBrBPr3EnV4XOj73j+5iu2zpgcrEkgxDoJEOHiCL72ygnOrlbbJqnz0XPNsGmrusayZC4Baa7yyYWl77j5hqTaJZMSiD8lAUms6U32vu3Gre/49NFrZjpHFvLZxWXY5DUisSZu+/xRltvJTZN7D5/+yW+64lmbJlbbXJEKESrmPKHcSsiGasumiXR578Sxdj7671li35nBDVumbCTGnnAVf04KDxBrXDJuYNlmXeBABiFUDK0shAEbjISEwDzxDOKiCVxQnCkGhCOGI3m7dKZtvzhI//jV89/36itnO85tm6oE4itna10AvaoiRVMn0QCOxDqD+IqUDAdydNSWAipZBbBljMSDNKXMYn7dDXOTqbQlqjCPxEIw1+8w1ymNiGopu1XdxcUQhHmiKamcGxV2z+zaUCUo4s/Qq/3i+fSOldybybjKdFmjFCIUg6a5de+Q2cnFZkR34oXP3Q7uKUjBeeIhKYDEuo1Tvbdu6/zLg6t7ZuPUcnvqzIgtGAsx9kSr+CogpKLCA4wCAWKNkQRGnCcEiDU2GMRXCWNLArxG0Zks1bxP71vaOL1dv/Y/7P5Lz9kykdphVlIppOCJIIxcSoQ3zvRxXnUJA53BaMQToxqsnGM5b6kYNS0zVfT64CKFxJc4KShlS9dQQS5WiEciINUdorQy4RPDMhiVyQpFKrZcUIB5wjiIY7ncOFd1eh0YkjpcWEAik/pBpmlXlkdAAeVMisFo9LF9p+lWZwp0Rj2NDiz22nYkV0nZhDAIsLDRGjygWtEknFLqsDgaLresMYixJ1zFVwtJIJk1lkGsM2uMAIGQMRiExJ878acMEQgVo4jJKIujpcXVib/x0v5bvvGy52+ftLNNKEEKZ1TxFbMxlgTUSZtmeieXV6qqYpiXzpyFzbbAFkI8HgY1g1UW24m5ODsy03W/W0MBbBDniTVKJApmXbFqHplBpRTWuBA+ttKM2gx1ziVSgHliGSuSy93FdoAKCi7IRFtVWFIijzzKgCFCEKfP5eOl7nm4mhP11Jv/w4HVaE6VkohJtXLwAGEHdgpVaBWfWB52+v2mMVnNYMDYJVPxVcBgmTU25xkwDzAPMg8Q68w68efPgAEJOWXnqKYYnhvGy5+14S0v3fXqZ2+YrEspTUQHUfOAiieCFIk1AuoqbtnW+d17htEVjI6dHBlsF7cEUEtcPAEnz67Slop0bJRfvWNivs+aDhQCzDqzxiYrFECQgj+LBKpKCRSWkwJCkVkXrBNPFAnaTMxFKAr0AoO4gACKYcWaIlKlAFKxk4DWwrmiGqIoKyeWPEGezy5BRmAeIlpQxi0E7Ipw8kQVhBSJsUumYuyJY6uVN6RyZtD+rRdd/k9eu3PbdDQuo5JqzCXWq9PLds7+7ifP5MmKqc47DgzftDLaMJGy66CVjcTFsJFo4AOHM7E6iglGzfM2tZtm+o3bKgJzIeaxMJgniXiAuXhmjXiAXEDGSoG7i0uDxdZUPSTcgrkQg32oExwdNW1m7JKpGHvCGCWUu6WhrW7cEtumOwNHr7Ql8shVl0uoFEfohh0dhrl2dXkv/fHdpw+dHG7YM1lcEAmDeGxs8yA1bfvhu47Sn8p5mehffdlm1rkYMM8cBgRGIAlDlLzytjc8a8P05Eqz2pHDYSUwFxbS0ihffcUMIImxS6Bi7IkTmZKICNSZqoDouGmkyu54BF0uGUnAdZfPsmN2b7OyrS443nP3uWfvmarctKoTF0ECVIzgzvuX//OxZkfdtwr53EuuvwkQpTiEreAZQ6xxpIBiK7Kxvu3mHRt6dSEHAeJiSIxdCsHYE8ACIVlJYBDPvnwzEEq1KqsuqculJGH7ys39v3vNTLuMMRP1L31475Gz55Q6OBsZcAZnYy4oQ7FsKG2h/PGdJ1geTXfSfcv+q8+b3zPfhwJJEkg8YwgwaG6iDtplaVqQO/sPLeIyaNqmFJdcXIpLcSkuxaW4FJfiYpfinN22uc1uITN2yQRjXyEbIxCUVCqDYUO9Y6qwLiSSSFxyNpBef8tmGnpoT+27D4/e+ccncQO2cMkFr8PiggKiDEdticTd+5e+/32Hd2/srHqFgf7GLVsna9mqVFWKFMEzz1QnvWLXBpoy3TEDf/7YElKKCBdFhCIUoQhFKEIRilBYYXBpUMLOBGOXTDD2RDBgW56mHB50Xr+zMztd8+SS3Lbti6+efusts19cbHKk7fPd73nXyY9/7ngdcm5ENsmKRLYLF9aWlGotN+Vn3nUvbY6K/efa1zx79huevZk1Es9ABgnnTif+yrVTLOWuMtJHv7B8zu7QJAWICxCoZFQZJQgXxi6ZYOwRmYtlFKWadUsVb7x582y/X4zEk0bI0K+qN3/j5UhuV4chtPz17zz1uePLqarbkrBxASRxAS5E5UT7b9514N9+4syeDTOd3NJ2f/AvzE/UdTbiGUmsKVaCF1w2SW6bXO/Z6H/58dNf3LcYqd+SwVyQc9SVmzpGjSqLsUsnGHsERgjxIPFnEGuEjLenlS8Oet/zwqlX3LARZ4knlZREk3n+ZdO/9vrLDp/SXGbrVH9w4OS3/fLn7jpyrqpSUMhNoTLiv1HMmgiW2/KvfmffD/72/bu2THZL84Uj8dPfvOklN2xv3AbmmUqYSFCuf9aWlz17w72DUeMG4p/+3r6Tw1EVVSk2j8CmWLWaRfU/dWiYaFqCsUsmGFtjsc5gLKKSs2mtRErSSLTCAZJAECAooRJESIUyX/eGg8Km2b/zjZdPd6q2tOJJZoWQyM1rXnHZ975q+96ToxlWt81O33Vk5bU/+8lb7zjSiKjqpEbOzrbJBRvjYocK8NnD5773l2//n999dPe2uSkPv3Do9P/0ys1/+y9dHUAOYZ6ZjFHQDkvZ2I23vHwHS2VK2j5R/uPnFv/Rv73j+LkmIgQFbFwyJbd2xhJJHDi9/AO/sfe3370vJBXGLp2KsS9nhEvryFR1ahktud4Q5FJGpQKZUlCShFWUwgR5c+V21JzszNz6rRtv3FaRhyX1eNIVYQOazSv/6K9dt5rLL7z3wNU7u/Vkd28Tf+nnPv+dLzryxpfsuO6y2W0z3SoBOSnAxe3CoNx36Ox/ufP09/3RWUblmtmCB/ccK6+7efs/esN1U2k1l7qK4BlLCIySKc6vfv7W7/q6k7/0kbPP2qQ9s9XbPj387LFP/tC3POu512zYPd2CRzEh2tp5daS7jizc8bmjb/rwgE+f+um/thPqRAsVY5dGxdh/yw5FRgtLq9RTk/XqoMkW5NRSSg05u0gR4TIZzKfufQvLzE28603Xv/q61JSQVHuEOjzJSpFSUYrsTdXwX3z71c+anfkHv30P09WN053VrdWv3TH4tds+e9Oe7ku2dbZv3bBxulfQwtLw6JGz958pv3+ycGZh97b+3ITvXAyWRz/1Fzf+rdfctLE7dCZLSkUEj0CABOKiCPEohEBckLgwgzhPrBNfAQM2kVSapkx32h953VV/dOyue/YuXjPf2TNdf2hh9KGfv/NrLp/52m3dy3dvnOocW27zoaPNkaMr//FYZmn1uRu5Y/PEiVWBW6nD2KVSMfblhFC4WZlg6oVXzP7BF04fWhj1Jic29yJ5dWRGOSJRoyqzQntyFOfa6nU3bfnhv7j1BZdPNJkULiQriSeZhAO3VJEq48kO3/+aHTdf0/m+37n/459dYk67pjU/O3VgqfziPYU7jzEcgOj2iEKVb6g7o61T9y4tHVju3HTl7D//lp1/4bmbhZtcO0ISzsggvlwIQl1BiPPEoxAQ6ovJUC3+W4IJsSWYFEhciJgKOtYZif+aAAFBX2wNOgLxWEiQ1A1ICPEgYVvJodzk3Rvi/d9944+8/Z5fvm2V2dXd3di8Y+L2hZVPHF/l9jO0LerTN9XgmpRGM707Tptq+DU3zEJbEYxdMhVjX86A2pEqaP/BN13xjdfOv/1Tx3/hjpMHl/qsiDBVoowwRM3M3Ouv43980ZYXX7NjrpdLbkUdFNtQUMWTyMbqJGV5DRVqDG5fev2md182/6HPnviNjx58++eGB0ertA0dUSWmJgjTZprE8vCzKZjQX71q+3e+cO7m52/a2uu6HeZIipBzailVFBQ8nI0Wm8y59rbJwkJuiwHb/Jlai6VyR4iV/JHVYsyfspEK/vwgs1yOV4Uh2ZxnEA+xYaV8LhdKpi7F4ssYlIs5l++yGBQmczGPyrDSwkJ727RZKE3OrBFrtKaMUqpMaprh1rmJn/2bz/nmFxz90fcevmvvyoECNfToVqLXGeaGgSjp8zW7NvJj3zz/379o65Xb59o8SKnL2CUj2zwaY6Gzw+Ytv37vv7v95FyfBYuno4Ddof0r5WPf+5wXXjVHyUQauuw9sXL73jOnzwwPnBwcWFU3tGe2unxr/6ZdU1fvnJvpBORcIoXAINsSIJ5cBmHWGATI4OIIAStte/Dk6qf2njp6dOXecz6wOFxsZDHX4frp7qYZ79g289zL5i6b7/U7FVAKCgsM4gHiy9ilHaq+675Tp5aaUvWaZvjs7ZNXbp7KeTVSLRIXcOjc4O59Z0vdK7md65RnXzY31e2U0kZULi1isUmf+uKJ1VIVKZXRjZdv2DHVoTSKGjAIlob5tntPiSjFCp535fx8PwxinUtDpCPn2s/sP12il0uerMtNV8xv6AhnVHEBTcl3Hzx76EyTur0yXN2zqb5u50blIUqOKjDIWNAWV9GCTq3En+w7ee++kwdP+Y7To5MlUqr21PmGDZ3dm7t7tvVfsGfjptkuYCPZSIxdKrLNozEWOjts3vLr9/6720/O9VmweDoK2B3sX/HH3vrsF16zoc1FoCihivNWR8NRkSL1OqlmjY1KzpIigq9WhlycAlEgAYPi4bDJFiaFJ7uljh7rWkqxOoDEo2pLDogQZNYl3JSCoyMU4pHZeER0eUjBslmjAOd2VKWEAIMgKLkUKVUSD2MQX1IgeIhdcm6qKrHOIAjatpBUJXFBpeSIALHOBTVtWydhRyQQD8nQ2rVzCBQQo8K5wci25KryZLdTkYCMEyomxNilVvFYGMQzhnAxBiQk5FLc2sKlU1W9SJApTUMVstxGqkAG8VVKkJRxtEqUViX3U+r3axDn2W5zsRDCUQWPUUImcnFLEiqFqLqKknKJlLgQqdB1aeVsVUZJlsLIBpxSnYlcbJBYE6pSBSWjxMPkdlQIRcglIiQeLqVOaxXbILEmpU5gSiYSF+BIjUu4FSoo3Haqujgi7NIqah6SSpvcltQpRW3OiaaOND/ZYV02FGvkJkEAUYcYexJUPBbiYQRmnUE8LRkX8yBlJUMISEVqXcIkFCqBFVEAOwCJr1ZS5AKyBKHWDrwOQshKYeOCFMFjZoVAlI6zwDJZUpQIYyEuwBQRpOTiEEK2iomwLVBQQhkXyHYoahuJhzNSVSWvKUoB4mFsKZSckwoukO2kqGwrgguT2wR2ZIWDKKnkrMCWlHiYopSjwq5Fp1Ljygo54wIUiKCSTSqOxNiTpOLR2EBBCWQVooUEwRoZCkYKbPP0YLB5kKBCSDbIKgWEomABwgQQEs4QIL4qmYhAGKIoAgkZW2s4TyFhYxCPWQGhMMoiF9doDcIgLigZS7aqABdIhhDCuCiSwSSTREXISCAKDyPAAkICgXgYycKWTDJJVEQYhGUQFyIwUqTaxm2OOlxEKUQmKr4khMjIFGUiRIBIKJk1TTjJYRkZxNiTouLRZBy2hUopDnIlqN0UV1ZYGSOweZDEGhvxVGSDyRJgIUABSIAIHhCIh4jzlPgqJh4gpOBBWsN5AgIIcVFCwXmSAqrgAcGjiRCINUIJCB4QigCEBIgvEZD4cpJAPBIpAIEA8SUSfyapEudJUCdAAREQ/FckEmuCxEPEGkGiZo0QAjH2ZKl4NMJFqaIkZ+iTmAo1UTUeyW7KhCm2CWPjxNOIGBsbe+qpeDQJWgRtU3HKCyzHgbYlxWTVm69Epx04lopycbZLiIcY83A2ayTGxsbGLqWKR1OskF3cTZ1//pev+O6vaW7be+z2Y4M/OJaXTw8ZDYmg09kY9Kskuw0tm4GdwWJsbGzsSVbxqIQoUPUUN22dvWmrX/Pc+eWifSeXj55aOn6qfGL/6Q+fTbcdX+b0CgRtS63Le3WrsuLSSCO7WC0KrFxykiMiyzbCgAwGYRDniXVmbGxs7CJVPJqQICHW2IAUTAXP2Tb5nG2T4NfkrYORl5eH9x9v7jq08rlDx995PN93bJnlTJWoBHmH6KV6UMVijpGVi51aG5kkGYpZJ7HGRkhyMQgKEg+wkRgbGxu7sIqLIfEAG9vFBqaD6Z7pd6/YVL/8humBt//9083y2YXPnkwf3Xtq34mFDy72Di+0DAcMRN2fiTKVSl06q+Js5Fa5ZMsdyWuwLcBrEGDM2NjY2GNX8bhISApc3GQSFg4TQekrP2s+Mb/5pivz6792ZsU6spCPnVxcXMgfv//0Hx5qP3x8eXG5JWfaPNWJrQklDcKtPYRVVGTzENuMjY2NXYSKr4CJQjdcFOCSXbILFpEa54Bamo6Y3hjXbNwE+VVfs+n7VvPCarn7yJkvHFm+69C5XzyspdMNgxFahSB0eV0RWnIeEA3KdpYYGxsbe8wqvgKCUNEa1oSUHKwRdMHCmDWWbYg63JnszEyyZ377Nz2b5ZYfXFhtm9GRs6MP3Lt4+NjKJ874E0eWWBxRiyrPJCZVd3BJ6VzxOReH5VKQCCtYUxorSZZtwjzAUtjGZo0AgRkbG3sGqPjKBMEDRILEQ4RYI9YISayTzXkGJiuu3NSD3jXb+fpr5rAPLZUDR8/tP83H7hv9yeHBh06fXhwMKGJpSK+zJ4gUgygtDN02pc2kllpCVjgVbFmSjUtBnGcsZMbGxp4ZKp5cEucJMHgNUsmWcoods9Wu2Q0vwX/lhWUlc+zsluPH8uFz+f6jJ99zaPU/H2k5u0rUKFNpT6cTpNWilTJYVW6rVEpQcClEKEIuCNuSDSYYGxt7Bqj4c2LWhQSUJFzqMgKGVIF6dadXeePW6tqtEWQz/zeW8vLS8OiJlffsW9x39MyvHm7uXwhGQ2KAaqrOJtMP2uRzpFWUS8agdWCB+BKDGRsbe3qq+GpgQVg9oIMLlGJRbIqzpSBvmYKpiSu2Tdz8nI2r5YofOrF64szSudX86YMrtx0cfexUOXTqLAOTC528o5siRc5RKEPFCs6lWDLrRMGgAIMxSHyJAYmxsbGnqIo/J+JLQgKZdUIJLISEwkJgvAYDgfrBdVv7123tA990E02bF4a+8/Dxw8eHXzjW/N79zacPLjFYRh0odLQzRbfqLrej1aQhJRtbmYA2yEUdS+RGEbYJQGDAyCoiMTY29tRR8VVDfIlYE6wR64SQ+BIbcIEIeh1t68S2a3dwLUP8dxaH51ZGB08sfO5Es//oyh3H8nuOrbI0ohXdRlG2RbeTlL26FN2VXAollRzhggpYCWds1hmDGBsbewqpeGqSACWKoXWES5RhoepUadd0MDN93baZVxUIjq6MDh89t3Cm/eDBwacPL//hqfbIySGDESVRa0O/O0nTuiqqB6UdJsKZSHVds8YoxNjY2FNKxVOZi5FDKojUw6UtOQi3paQIDSmxtV9tu3IjlK9/Pk1uTi6Xew4tHTo9PHgmf/LIym8fOHvmdCEl2lU6aU9dNlRlf3RSBBiEhRgbG3sKqXhKiwQEWVgIYYWQnBOtVUNktyohkRSprnfPsXtuAsiwsNz8bNPef3LwyfuH9x1dvO3w8h8fbe4/M6JplkcjIDDrxNjY2FNHxVOZeECSeEDivFQBAkSo5iEmGTDgJM1P1vPUu+f6X3eVC9uPLAyPLqyePDv4J//lSO4IEMVUYmxs7KlEtnlGMmDAoNatRKWAAN91bLB7OmYnOtkRshBjY2NPHbLNM57dGmMZMCkFVosCBy2qGRsbe+qoGAODESTWiFKKFUERpRDB2NjYU4lsM4ZtQIAoFiCVFkVWSoyNjT2VyDZjY2NjTyPB2NjY2NNLMDY2Nvb0EoyNjY09vQRjY2NjTy/B2NjY2NNLMDY2Nvb0EoyNjY09vQRjY2NjTy/B2NjY2NNLMDY2Nvb0EoyNjY09vQRjY2NjTy/B2NjY2NNLMDY2Nvb0EoyNjY09vQRjY2NjTy/B2NjY2NPL/w+2ikOHFPFIrwAAAABJRU5ErkJggg==" />

<br><br>

<b>Total Size: </b>$($M365Sizing[2].TotalSizeGB) GB<br>
<b>Average Growth Forecast (Yearly): </b>$($M365Sizing[2].AverageGrowthPercentage) %<br>
<b>Number of Sites: </b>$($M365Sizing[2].NumberOfSites)<br>
<b>First Year Front-End Storage Used: </b>($M365Sizing[2].firstYearFrontEndStorageUsed) GB<br>
<b>Second Year Front-End Storage Used: </b>$($M365Sizing[2].thirdYearFrontEndStorageUsed) GB<br>
<b>Third Year Front-End Storage Used: </b>$($M365Sizing[2].thirdYearFrontEndStorageUsed) GB<br>

<br><br>

<hr>

<big><big><big><b>Total Numbers</b></big></big></big><br>
<b>Total Users: </b>$UserLicensesRequired<br>
<b>First Year Total Front-End Storage: </b>$($M365Sizing[4].firstYearTotalUsage) GB<br>
<b>Second Year Total Front-End Storage: </b>$($M365Sizing[4].thirdYearTotalUsage) GB<br>
<b>Third Year Total Front-End Storage: </b>$($M365Sizing[4].thirdYearTotalUsage) GB<br>

</body>
</html>
"@

# Export report
Write-Host "Exporting report to $export" -ForegroundColor Yellow
Write-Output $HTML_CODE | Out-File -FilePath .\($export) -Append
