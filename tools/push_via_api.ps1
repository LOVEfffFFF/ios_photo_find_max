# Push local HEAD to GitHub through the Git Data API.
#
# Why: on this machine git-over-HTTPS to github.com gets reset / times out,
# while api.github.com works. So we build blob -> tree -> commit -> ref by hand.
#
# NOTE: deliberately ASCII-only. PowerShell 5.1 reads BOM-less .ps1 as ANSI,
# so CJK text inside string literals becomes mojibake and breaks quoting.
#
# Usage: powershell -ExecutionPolicy Bypass -File tools\push_via_api.ps1
# Assumes: repo already committed locally (git ls-files lists what to push).

$ErrorActionPreference = 'Stop'

$repo = 'LOVEfffFFF/ios_photo_find_max'
$root = 'c:\Users\OXO\Desktop\ios_photo_find_max'
$branch = 'main'

Push-Location $root
$files = @(git ls-files | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$localSha = (git rev-parse HEAD | Out-String).Trim()
$message = (git log -1 --format=%B | Out-String).TrimEnd()
Pop-Location

if ($files.Count -eq 0) { throw 'no tracked files found (did you commit?)' }
Write-Output ("tracked files: " + $files.Count)
Write-Output ("local HEAD   : " + $localSha)

$tmp = Join-Path $env:TEMP ('ghpush_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-GhJson {
    param([string]$Method, [string]$Path, $Body, [string]$Jq = '.sha')
    $f = Join-Path $tmp ([guid]::NewGuid().ToString('N') + '.json')
    $json = $Body | ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText($f, $json, $utf8)
    $out = & gh api --method $Method $Path --input $f --jq $Jq 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("gh api $Method $Path failed: " + ($out | Out-String)) }
    return ($out | Out-String).Trim()
}

try {
    $parent = $null
    $parentTree = $null
    # Listing branches exits 0 even for an empty repo; a GET on a missing branch
    # would exit non-zero with stderr, which PS 5.1 turns into a terminating error.
    $branches = (& gh api "repos/$repo/branches" --jq '.[].name' 2>$null | Out-String).Trim()
    if ($branches -match ("(?m)^" + $branch + "$")) {
        $parent = (& gh api "repos/$repo/branches/$branch" --jq .commit.sha 2>$null | Out-String).Trim()
        # base_tree must be a TREE sha, not the commit sha
        $parentTree = Invoke-GhJson -Method GET -Path "repos/$repo/git/commits/$parent" -Body $null -Jq '.tree.sha'
        Write-Output "parent commit = $parent"
        Write-Output "parent tree   = $parentTree"
    } else {
        Write-Output 'no existing branch, this will be the first commit'
    }

    $entries = @()
    foreach ($rel in $files) {
        $abs = Join-Path $root ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $abs)) { throw "missing file: $rel" }
        $bytes = [IO.File]::ReadAllBytes($abs)
        $b64 = [Convert]::ToBase64String($bytes)
        $blobSha = Invoke-GhJson -Method POST -Path "repos/$repo/git/blobs" -Body @{
            content  = $b64
            encoding = 'base64'
        }
        Write-Output ("blob  {0,-45} {1,8} B  {2}" -f $rel, $bytes.Length, $blobSha)
        $entries += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $blobSha }
    }

    $treeBody = @{ tree = $entries }
    if ($parentTree) { $treeBody['base_tree'] = $parentTree }
    $newTree = Invoke-GhJson -Method POST -Path "repos/$repo/git/trees" -Body $treeBody
    Write-Output "new tree      = $newTree"

    $parents = @()
    if ($parent) { $parents = @($parent) }
    $newCommit = Invoke-GhJson -Method POST -Path "repos/$repo/git/commits" -Body @{
        message = $message
        tree    = $newTree
        parents = $parents
    }
    Write-Output "new commit    = $newCommit"

    if ($parent) {
        $rf = Join-Path $tmp 'ref.json'
        [IO.File]::WriteAllText($rf, (@{ sha = $newCommit; force = $false } | ConvertTo-Json -Compress), $utf8)
        & gh api --method PATCH "repos/$repo/git/refs/heads/$branch" --input $rf 2>&1 | Out-String | Write-Output
        if ($LASTEXITCODE -ne 0) { throw 'ref update failed' }
    } else {
        $cf = Join-Path $tmp 'create.json'
        [IO.File]::WriteAllText($cf, (@{ ref = "refs/heads/$branch"; sha = $newCommit } | ConvertTo-Json -Compress), $utf8)
        & gh api --method POST "repos/$repo/git/refs" --input $cf 2>&1 | Out-String | Write-Output
        if ($LASTEXITCODE -ne 0) { throw 'ref creation failed' }
    }

    $now = (& gh api "repos/$repo/branches/$branch" --jq .commit.sha 2>&1 | Out-String).Trim()
    Write-Output "remote head   = $now"
    if ($now -eq $localSha) {
        Write-Output 'SHA_MATCH: remote commit is identical to the local one.'
    } else {
        Write-Output "SHA_DIFF: remote $now vs local $localSha (content synced, object differs)"
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
