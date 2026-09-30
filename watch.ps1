$ErrorActionPreference = "Stop"

$Handle = "FortniteStatus"
$Webhook = $env:TEAMS_WEBHOOK_URL
if ([string]::IsNullOrWhiteSpace($Webhook)) {
    throw "TEAMS_WEBHOOK_URL is missing"
}

$StateFile = Join-Path $PSScriptRoot "seen.json"
$Api = "https://api.fxtwitter.com/2/profile/$Handle/statuses?count=20"

function Get-Json($Url) {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = "fnstatus-watcher/1.0"
    $req.Timeout = 30000
    $resp = $req.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $reader.Close()
        return $text | ConvertFrom-Json
    }
    finally {
        $resp.Close()
    }
}

function Get-Seen {
    if (Test-Path $StateFile) {
        $raw = Get-Content -Raw -Path $StateFile
        if ([string]::IsNullOrWhiteSpace($raw)) { return [System.Collections.Generic.HashSet[string]]::new() }
        $arr = $raw | ConvertFrom-Json
        $set = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($id in @($arr)) { [void]$set.Add([string]$id) }
        return $set
    }
    return [System.Collections.Generic.HashSet[string]]::new()
}

function Save-Seen($Ids) {
    $list = @($Ids) | Sort-Object
    if ($list.Count -gt 200) {
        $list = $list | Select-Object -Last 200
    }
    ($list | ConvertTo-Json -Compress) | Set-Content -Path $StateFile -Encoding utf8
}

function Test-Reply($Post) {
    $text = [string]$Post.text
    if ($text.TrimStart().StartsWith("@")) { return $true }
    if ($Post.replying_to -or $Post.in_reply_to) { return $true }
    if ($Post.reply -and ($Post.reply.in_reply_to_status_id -or $Post.reply.in_reply_to_screen_name)) { return $true }
    return $false
}

function Get-PostUrl($Post) {
    if ($Post.url) { return [string]$Post.url }
    return "https://x.com/$Handle/status/$($Post.id)"
}

function Get-NormalizedPost($Item) {
    if ($Item.type -eq "status" -and $Item.status) { return $Item.status }
    return $Item
}

function Send-TeamsCard($Text, $Url) {
    $payload = @{
        type = "message"
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
                        @{ type = "TextBlock"; wrap = $true; text = $Text }
                        @{ type = "TextBlock"; wrap = $true; isSubtle = $true; text = $Url }
                    )
                }
            }
        )
    }

    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri $Webhook -Method Post -Body $json -ContentType "application/json; charset=utf-8" | Out-Null
}

$seen = Get-Seen
$firstRun = ($seen.Count -eq 0)
$data = Get-Json $Api

$posts = @()
if ($data.results) { $posts = @($data.results) }
elseif ($data.timeline) { $posts = @($data.timeline) }

$foundIds = New-Object System.Collections.Generic.List[string]
$toSend = New-Object System.Collections.Generic.List[object]

foreach ($item in $posts) {
    $post = Get-NormalizedPost $item
    $pid = [string]$post.id
    if ([string]::IsNullOrWhiteSpace($pid)) { continue }
    $foundIds.Add($pid)
    if ($seen.Contains($pid)) { continue }
    if (Test-Reply $post) { continue }
    $toSend.Add($post)
}

if ($firstRun) {
    foreach ($id in $foundIds) { [void]$seen.Add($id) }
    Save-Seen $seen
    Write-Host "Primed $($foundIds.Count) posts, nothing sent"
    exit 0
}

$toSend = $toSend | Sort-Object { [int64]$_.id }
foreach ($post in $toSend) {
    Send-TeamsCard ([string]$post.text) (Get-PostUrl $post)
    Write-Host "Sent $($post.id)"
}

foreach ($id in $foundIds) { [void]$seen.Add($id) }
Save-Seen $seen
