# users.json file
$usersJsonPath = (Join-Path (Split-Path -parent (Split-Path -parent $MyInvocation.MyCommand.Definition)) "users.json")


if(Test-Path $usersJsonPath -PathType Leaf) {
    Write-Host "Hashing passwords in $usersJsonPath"
    $users = Get-Content $usersJsonPath | ConvertFrom-Json | ForEach-Object {
        if($_.password.Split(":")[0] -ne "sha256") {
            Write-Host -ForegroundColor Yellow "Hashing password for user: $($_.username)"
            # generate sha256 hash of password
            $password = $_.password
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($password))
            $hashString = [System.BitConverter]::ToString($hash) -replace '-'
            $_.password = "sha256:$hashString".ToLower()
        }
        else {
            Write-Host -ForegroundColor Green "Password for user is already hashed: $($_.username)"
        }
        $_
    }
    $users | ConvertTo-Json | Set-Content $usersJsonPath
}
else {
    Write-Host "No users.json file found in: $usersJsonPath"
}
