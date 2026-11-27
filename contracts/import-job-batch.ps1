param(
    [Parameter(Mandatory)][string]$Provider,
    [Parameter(Mandatory)][string]$InputFile,
    [uri]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateSet('live', 'curated', 'open_data', 'mock')][string]$DataStatus
)

$ErrorActionPreference = 'Stop'
if (-not $env:INTEGRATION_KEY) {
    throw 'Set INTEGRATION_KEY for the target Backend before importing jobs.'
}
if (-not $BaseUrl.IsAbsoluteUri -or
    ($BaseUrl.Scheme -ne 'https' -and -not ($BaseUrl.IsLoopback -and $BaseUrl.Scheme -eq 'http'))) {
    throw 'Use an HTTPS Backend URL or an HTTP loopback address.'
}

function Read-Number([string]$Text) {
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        [double]::Parse($Text, [Globalization.CultureInfo]::InvariantCulture)
    }
}

$extension = [IO.Path]::GetExtension($InputFile).ToLowerInvariant()
$items = @(switch ($extension) {
    '.json' {
        $value = Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($value.PSObject.Properties['items']) { $value.items }
        else { $value }
    }
    '.csv' {
        foreach ($row in Import-Csv -LiteralPath $InputFile -Encoding UTF8) {
            $item = @{
                externalId = $row.externalId
                title = $row.title
                category = $row.category
                mapGroup = 'job'
                sourceUrl = $row.sourceUrl
                location = @{ precision = 'none' }
                money = @{ basis = 'none' }
            }
            foreach ($field in 'organization', 'postedAt', 'updatedAt', 'expiresAt', 'status') {
                if ($row.$field) { $item[$field] = $row.$field }
            }
            foreach ($field in 'province', 'district', 'workMode', 'precision') {
                if ($row.$field) { $item.location[$field] = $row.$field }
            }
            if ($row.locationText) { $item.location.text = $row.locationText }
            foreach ($field in 'lat', 'lng') {
                if ($row.$field) { $item.location[$field] = Read-Number $row.$field }
            }
            if ($row.moneyBasis) { $item.money.basis = $row.moneyBasis }
            if ($row.moneyMin) { $item.money.min = Read-Number $row.moneyMin }
            if ($row.moneyMax) { $item.money.max = Read-Number $row.moneyMax }
            if ($row.moneyUnit) { $item.money.unit = $row.moneyUnit }
            if ($row.skills) { $item.skills = @($row.skills -split '\|') }
            if ($row.conditions) { $item.conditions = @($row.conditions -split '\|') }
            if ($row.forOlder) { $item.forOlder = [bool]::Parse($row.forOlder) }
            $item
        }
    }
    default { throw 'The input must be a UTF-8 CSV or JSON file.' }
})
if (!$items.Count -or ($items | Where-Object { $_.mapGroup -ne 'job' -or -not $_.sourceUrl })) {
    throw 'Supply at least one job. Every job must include sourceUrl.'
}

$url = [uri]::new($BaseUrl, '/v1/integrations/opportunities/batch')
for ($offset = 0; $offset -lt $items.Count; $offset += 500) {
    $end = [Math]::Min($offset + 499, $items.Count - 1)
    $body = @{ provider = $Provider; items = @($items[$offset..$end]) }
    if ($DataStatus) { $body.dataStatus = $DataStatus }
    $request = @{
        Uri = $url
        Method = 'Post'
        Headers = @{ 'X-Api-Key' = $env:INTEGRATION_KEY }
        ContentType = 'application/json; charset=utf-8'
        Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 16 -Compress))
    }
    $result = Invoke-RestMethod @request
    [pscustomobject]@{
        offset = $offset
        accepted = $result.accepted
        rejected = @(foreach ($row in $result.rejected) {
            @{ index = $offset + $row.index; reason = $row.reason }
        })
        merged = @(foreach ($row in $result.merged) {
            @{ index = $offset + $row.index; existingId = $row.existingId }
        })
    }
}
