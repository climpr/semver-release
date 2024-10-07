[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet("major", "minor", "patch")]
    [string]
    $UpdateType,

    [Parameter(Mandatory = $false)]
    [string]
    $Label,

    [Parameter(Mandatory = $false)]
    [bool]
    $PreRelease = $false
)

#* Defaults
$semverRegex = "^(v)?((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?)$"

$releases = gh release list --json "name,tagName,isLatest,isPrerelease,isDraft" | ConvertFrom-Json -NoEnumerate

$semverReleases = $releases | Where-Object { $_.tagName -match $semverRegex }

$latestSemver = $semverReleases.tagName | Sort-Object { ($_ -replace '^v' -replace '-.+$') -as [version] }, { $_ } | Select-Object -Last 1

if ($latestSemver) {
    $null = $latestSemver -match $semverRegex
    $prefix = $Matches[1]

    $newMajor = [int]$Matches[3]
    $newMinor = [int]$Matches[4]
    $newPatch = [int]$Matches[5]
          
    switch ($UpdateType) {
        "major" {
            $newMajor++
            $newMinor = 0
            $newPatch = 0
        }
        "minor" {
            $newMinor++
            $newPatch = 0
        }
        "patch" { $newPatch++ }
    }
}
else {
    $prefix = 'v'
    $newMajor = 0
    $newMinor = 1
    $newPatch = 0
}

#* Calculate semver tags
$newSemver = "$($prefix)$($newMajor).$($newMinor).$($newPatch)"
$newSemverMinor = "$($prefix)$($newMajor).$($newMinor)"
$newSemverMajor = "$($prefix)$($newMajor)"

#* Append label if applicable
if ($Label) { $newSemver = "$newSemver-$($Label.TrimStart('-'))" }

#* Create full semver release
Write-Host "Releasing $newSemver"
git tag -fa $newSemver -m "Automated release: $newSemver"
git push --tags --force

if (!$Label -and !$PreRelease) {
    gh release create $newSemver --latest --generate-notes
}
else {
    gh release create $newSemver --latest=false --prerelease=$($PreRelease.ToString().ToLower()) --generate-notes
}

#* Create/Update minor release tag. Only if label is not present and release is not tagged as pre-release
if (!$Label -and !$PreRelease) {
    git tag -fa $newSemverMinor -m "Automated release: $newSemverMinor"
    git push --tags --force

    $existingMinor = $releases | Where-Object { $_.tagName -eq $newSemverMinor }
    $releaseMinor = !$existingMinor -or $UpdateType -eq "minor"
    if ($releaseMinor) {
        Write-Host "Releasing $newSemverMinor"
        if ($releases | Where-Object { $_.tagName -eq $newSemverMinor }) {
            Write-Host "Deleting old release $newSemverMinor"
            gh release delete $newSemverMinor --cleanup-tag -y
        }

        $previousMinor = $newMinor -gt 0 ? $newMinor - 1 : 0
        $previousSemverMinor = "$($prefix)$($newMajor).$($previousMinor)"
        if ($releases | Where-Object { $_.tagName -eq $previousSemverMinor }) {
            gh release create $newSemverMinor --latest=false --generate-notes --notes-start-tag $previousSemverMinor
        }
        else {
            $repoName = gh repo view --json url -q ".url"
            gh release create $newSemverMinor --latest=false --notes "**Full Changelog**: $repoName/commits/$newSemverMinor"
        }
    }

    #* Create/Update major release tag. Only if label is not present
    git tag -fa $newSemverMajor -m "Automated release: $newSemverMajor"
    git push --tags --force

    $existingMajor = $releases | Where-Object { $_.tagName -eq $newSemverMajor }
    $releaseMajor = !$existingMajor -or $UpdateType -eq "major"
    if ($releaseMajor) {
        Write-Host "Releasing $newSemverMajor"
        if ($releases | Where-Object { $_.tagName -eq $newSemverMajor }) {
            Write-Host "Deleting old release $newSemverMajor"
            gh release delete $newSemverMajor --cleanup-tag -y
        }

        $previousMajor = $newMajor -gt 0 ? $newMajor - 1 : 0
        $previousSemverMajor = "$($prefix)$($previousMajor)"
        if ($releases | Where-Object { $_.tagName -eq $previousSemverMajor }) {
            gh release create $newSemverMajor --latest=false --generate-notes --notes-start-tag $previousSemverMajor
        }
        else {
            $repoName = gh repo view --json url -q ".url"
            gh release create $newSemverMajor --latest=false --notes "**Full Changelog**: $repoName/commits/$newSemverMajor"
        }
    }
}