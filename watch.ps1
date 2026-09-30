$ErrorActionPreference = "Stop"

$AccountHandle = "FortniteStatus"
$WebhookUrl = $env:TEAMS_WEBHOOK_URL
if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    throw "TEAMS_WEBHOOK_URL is missing"
}

$StatePath = Join-Path -Path $PSScriptRoot -ChildPath "seen.json"
$TimelineUrl = "https://api.fxtwitter.com/2/profile/$AccountHandle/statuses?count=20"

function Read-RemoteJson {
    param([string]$Url)

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "fnstatus-watcher/1.0"
    $request.Timeout = 30000
    $response = $request.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $raw = $reader.ReadToEnd()
        $reader.Close()
        return $raw | ConvertFrom-Json
    }
    finally {
        $response.Close()
    }
}

function Read-SeenIds {
    $box = [System.Collections.Generic.HashSet[string]]::new()
    if (-not (Test-Path -Path $StatePath)) {
        return $box
    }

    $raw = Get-Content -Path $StatePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $box
    }

    foreach ($value in @($raw | ConvertFrom-Json)) {
        [void]$box.Add([string]$value)
    }
    return $box
}

function Write-SeenIds {
    param($IdSet)

    $ordered = @($IdSet) | Sort-Object
    if ($ordered.Count -gt 200) {
        $ordered = $ordered | Select-Object -Last 200
    }

    $json = $ordered | ConvertTo-Json -Compress
    if ([string]::IsNullOrWhiteSpace($json)) {
        $json = "[]"
    }
    Set-Content -Path $StatePath -Value $json -Encoding utf8
}

function Test-IsReplyPost {
    param($Status)

    $bodyText = [string]$Status.text
    if ($bodyText.TrimStart().StartsWith("@")) {
        return $true
    }
    if ($Status.replying_to -or $Status.in_reply_to) {
        return $true
    }
    if ($Status.reply -and ($Status.reply.in_reply_to_status_id -or $Status.reply.in_reply_to_screen_name)) {
        return $true
    }
    return $false
}

function Get-StatusUrl {
    param($Status)

    if ($Status.url) {
        return [string]$Status.url
    }
    return "https://x.com/$AccountHandle/status/$($Status.id)"
}

function Get-StatusObject {
    param($Entry)

    if ($Entry.type -eq "status" -and $Entry.status) {
        return $Entry.status
    }
    return $Entry
}

function Send-TeamsCard {
    param(
        [string]$MessageText,
        [string]$PostLink
    )

    $payload = @{
        type        = "message"
        attachments = @(
            @{
                contentType = "application/vnd.microsoft.card.adaptive"
                contentUrl  = $null
                content     = @{
                    '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                    type      = "AdaptiveCard"
                    version   = "1.3"
                    body      = @(
                        @{ type = "TextBlock"; weight = "Bolder"; size = "Medium"; text = "Fortnite Status" }
                        @{ type = "TextBlock"; wrap = $true; text = $MessageText }
                        @{ type = "TextBlock"; wrap = $true; isSubtle = $true; text = $PostLink }
                    )
                }
            }
        )
    }

    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $json -ContentType "application/json; charset=utf-8" | Out-Null
}

$seenIds = Read-SeenIds
$isFirstRun = ($seenIds.Count -eq 0)
$timeline = Read-RemoteJson -Url $TimelineUrl

$entries = @()
if ($timeline.results) {
    $entries = @($timeline.results)
}
elseif ($timeline.timeline) {
    $entries = @($timeline.timeline)
}

$foundIds = New-Object System.Collections.Generic.List[string]
$pending = New-Object System.Collections.Generic.List[object]

foreach ($entry in $entries) {
    $status = Get-StatusObject -Entry $entry
    $statusId = [string]$status.id
    if ([string]::IsNullOrWhiteSpace($statusId)) {
        continue
    }

    $foundIds.Add($statusId)
    if ($seenIds.Contains($statusId)) {
        continue
    }
    if (Test-IsReplyPost -Status $status) {
        continue
    }
    $pending.Add($status)
}

if ($isFirstRun) {
    foreach ($statusId in $foundIds) {
        [void]$seenIds.Add($statusId)
    }
    Write-SeenIds -IdSet $seenIds
    Write-Host "Primed $($foundIds.Count) posts, nothing sent"
    exit 0
}

$pending = $pending | Sort-Object { [int64]$_.id }
foreach ($status in $pending) {
    Send-TeamsCard -MessageText ([string]$status.text) -PostLink (Get-StatusUrl -Status $status)
    Write-Host "Sent $($status.id)"
}

foreach ($statusId in $foundIds) {
    [void]$seenIds.Add($statusId)
}
Write-SeenIds -IdSet $seenIds
