# Set the output file name
$OutputFile = Join-Path $PSScriptRoot "all_for_ai.txt"

# Delete the old output file if it exists
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

# The file types we want to compile
$Extensions = @("*.godot", "*.gd", "*.tscn", "*.tres", "*.cfg")

# Get all matching files recursively, ignoring the .godot cache folder
$Files = Get-ChildItem -Path $PSScriptRoot -Recurse -Include $Extensions -File | 
         Where-Object { $_.FullName -notmatch '\\.godot\\' -and $_.FullName -ne $OutputFile }

# Create the file and write a header
$Header = "PROJECT COMPILATION FOR AI`nGenerated on: $(Get-Date)`nTotal Files: $($Files.Count)`n"
$Header | Out-File -FilePath $OutputFile -Encoding UTF8

# Loop through each file and append its contents
foreach ($File in $Files) {
    # Get the path relative to the project root
    $RelativePath = $File.FullName.Replace($PSScriptRoot, "").TrimStart('\')
    
    # Create a clear visual separator
    $Separator = "`n" + ("=" * 80) + "`n" + "FILE: $RelativePath" + "`n" + ("=" * 80) + "`n"
    
    # Write the separator and the file contents
    $Separator | Out-File -FilePath $OutputFile -Append -Encoding UTF8
    Get-Content $File.FullName | Out-File -FilePath $OutputFile -Append -Encoding UTF8
}

Write-Host "Compilation complete! File saved to: $OutputFile" -ForegroundColor Green