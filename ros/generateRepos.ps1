[CmdletBinding()]
param(
    $badParam,
    [Parameter(Mandatory=$True)][string]$Distro,
    [Parameter(Mandatory=$True)][string]$Version,
    [Parameter(Mandatory=$True)][string[]]$Packages
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
# Powershell2-compatible way of forcing named-parameters
if ($badParam)
{
    throw "Only named parameters are allowed"
}

try
{
    function Remove-BomFromFile($OldPath, $NewPath)
    {
        $Content = Get-Content $OldPath -Raw
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
        [System.IO.File]::WriteAllLines($NewPath, $Content, $Utf8NoBomEncoding)
    }

    # $scriptsDir = split-path -parent $script:MyInvocation.MyCommand.Definition
    $rosdistroDir = Join-Path $Env:Temp $(New-Guid)

    Set-Alias python (get-command 'python.exe').Path -Scope Script
    Set-Alias git (get-command 'git.exe').Path -Scope Script
    Set-Alias rosinstall_generator (get-command 'rosinstall_generator.exe').Path -Scope Script

    # ensure the temp folder doesn't exist.
    Remove-Item $rosdistroDir -Force -Recurse -ErrorAction SilentlyContinue
    if (Test-Path $rosdistroDir -PathType Container) {
        throw "Cannot remove $rosdistroDir"
    }

    git clone https://github.com/ros/rosdistro "$rosdistroDir"
    git "--git-dir=${rosdistroDir}\.git" "--work-tree=${rosdistroDir}" checkout "$Version"

    python (get-command 'rosdistro_build_cache').Path --ignore-local --debug "file://localhost/$rosdistroDir\index-v4.yaml" "$Distro"

    $cacheFilePath = (Join-Path (Get-Location).Path "$Distro-cache.yaml.gz")
    if (-Not (Test-Path $cacheFilePath -PathType Leaf)) {
        throw "Cannot find $cacheFilePath"
    }

    $indexYaml = @"
%YAML 1.1
# ROS index file
# see REP 153: http://ros.org/reps/rep-0153.html
---
distributions:
  ${Distro}:
    distribution: [${Distro}/distribution.yaml]
    distribution_cache: file://localhost/${cacheFilePath}
    distribution_status: active
    distribution_type: ros1
    python_version: 3
type: index
version: 4
"@

    $indexYamlFile = (Join-Path $rosdistroDir "index-snapshot.yaml")
    Out-File -filepath $indexYamlFile -inputobject $indexYaml -Encoding "utf8"

    $Env:ROSDISTRO_INDEX_URL = "file://localhost/$indexYamlFile"

    $generatedRepos = (Join-Path (Get-Location).Path "${Distro}.repos")
    rosinstall_generator $Packages --rosdistro $Distro --upstream --deps --format repos | Out-File $generatedRepos -Encoding "utf8"

    # ensure the temp folder to be cleaned up.
    Remove-Item $rosdistroDir -Force -Recurse -ErrorAction SilentlyContinue
    if (Test-Path $rosdistroDir -PathType Container) {
        throw "Cannot remove $rosdistroDir"
    }

    Remove-BomFromFile -OldPath $generatedRepos -NewPath $generatedRepos
}
catch
{
  Write-Warning "Failed to generate repos."
  throw
}
