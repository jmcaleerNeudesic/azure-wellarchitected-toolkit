Param
(
    [Parameter (Mandatory=$false)]
    [object]$WebhookData
)
    
$slackChannelUrl = Get-AutomationVariable -Name SlackChannelUrl

if ($WebhookData)
{
    $slackBody = $null

    Write-Output "Webhook request body: $($WebhookData.RequestBody)"

    $alertBodyString = $WebhookData.RequestBody | Out-String
    $alertBody = (ConvertFrom-Json -InputObject $alertBodyString)

    $alertEssentials = [object] ($alertBody.data).essentials
    $AlertContext = [object] ($alertBody.data).alertContext

    $signalType = $alertEssentials.signalType
    $targetIds = $alertEssentials.alertTargetIds -join ','
    $configurationItems = $alertEssentials.configurationItems -join ','

    $alertDescription = $alertEssentials.description

    switch ($alertEssentials.severity)
    {
        "Sev1" { $attachmentColor = "warning" }
        "Sev0" { $attachmentColor = "danger" }
        Default { $attachmentColor = "#439FE0" }
    }

    if ($alertEssentials.monitorCondition -eq "Resolved")
    {
        $attachmentColor = "good"
    }

    if ($alertEssentials.monitorCondition -eq "Fired")
    {
        $timestamp = $alertEssentials.firedDateTime
    }
    else
    {
        $timestamp = $alertEssentials.resolvedDateTime
    }

    $attachmentFields = @()
    $attachmentFields += New-Object PSObject -Property @{
        title = "Severity"
        value = $alertEssentials.severity
        short = 'true'
    }
    $attachmentFields += New-Object PSObject -Property @{
        title = "Status"
        value = $alertEssentials.monitorCondition
        short = 'true'
    }
    $attachmentFields += New-Object PSObject -Property @{
        title = "Timestamp"
        value = $timestamp
        short = 'false'
    }
    $attachmentFields += New-Object PSObject -Property @{
        title = "Configuration items"
        value = $configurationItems
        short = 'false'
    }
    $attachmentFields += New-Object PSObject -Property @{
        title = "Target IDs"
        value = $targetIds
        short = 'false'
    }

    if ($signalType -eq "Metric") {
        # This is the near-real-time Metric Alert schema
    }
    elseif ($signalType -eq "Log") {

        $linkToSearchResults = $AlertContext.LinkToSearchResults

        $resultsCount = "N/A"
        if ($AlertContext.SearchResults.tables)
        {
            $resultsCount = $AlertContext.SearchResults.tables[0].rows.Count
        }

        $attachmentFields += New-Object PSObject -Property @{
            title = "Log search results ($resultsCount rows)"
            value = "<$linkToSearchResults|click here>"
            short = 'true'
        }
    }
    elseif ($signalType -eq "Activity Log") {

        switch ($AlertContext.level)
        {
            "Informational" { $attachmentColor = "#439FE0" }
            "Warning" { $attachmentColor = "warning" }
            "Error" { $attachmentColor = "danger" }
            "Resolved" { $attachmentColor = "good" }
            Default { $attachmentColor = "#000000" }
        }

        if ($alertEssentials.monitoringService -eq "Resource Health")
        {
            $incidentType = $AlertContext.properties.type
            $impactStartTime = $AlertContext.eventTimestamp
        }
        elseif ($alertEssentials.monitoringService -eq "ServiceHealth") {
            $incidentType = $AlertContext.properties.incidentType
            $impactStartTime = $AlertContext.properties.impactStartTime
        }
        else {
            $incidentType = "N/A"
            $impactStartTime = "N/A"
        }

        $attachmentFields += New-Object PSObject -Property @{
            title = "Level"
            value = $AlertContext.level
            short = 'true'
        }
        $attachmentFields += New-Object PSObject -Property @{
            title = "Incident Type"
            value = $incidentType
            short = 'true'
        }
        $attachmentFields += New-Object PSObject -Property @{
            title = "Impact Start Time"
            value = $impactStartTime
            short = 'false'
        }

        if ($AlertContext.properties.communication)
        {
            $alertDescription = $AlertContext.properties.communication
            $alertDescription = $alertDescription -replace '<[^>]+>',''    
        }
    }
    else {
        # The schema isn't supported.
        Write-Error "The alert data schema - $schemaId - is not supported."
    }
    
    $slackAttachments = @()

    $alertText = "$alertDescription ($configurationItems)"
    $alertTitle = "Azure Monitor $signalType Alert - $($alertEssentials.alertRule)" 

    $slackAttachments += New-Object PSObject -Property @{
        color = $attachmentColor;
        title = $alertTitle;
        text  = $alertText;
        fields = $attachmentFields;
    }

    $slackBody = @{ 
        "text" = "*``Azure Monitor``*";                       
        "attachments" = $slackAttachments;
    } | ConvertTo-Json -Depth 5

    Write-Host $slackBody

    if ($slackBody -ne $null)
    {
        $slackChannels = $slackChannelUrl.Split(",")
        foreach ($slackChannel in $slackChannels)
        {
            Invoke-RestMethod -Uri $slackChannel -Method Post -body $slackBody -ContentType 'application/json; charset=utf-8'
        }        
     }

}
else {
    # Error
    Write-Error "This runbook is meant to be started from an Azure alert webhook only."
}