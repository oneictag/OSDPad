$subjectName = "OSDCloudRegistration"

$newCert = @{
    Subject           = "CN=$($subjectName)"
    CertStoreLocation = "Cert:\LocalMachine\My"
    KeyExportPolicy   = "Exportable"
    KeySpec           = "Signature"
    KeyLength         = "2048"
    KeyAlgorithm      = "RSA"
    HashAlgorithm     = "SHA512"
    NotAfter          = (Get-Date).AddMonths(60) #5 years validity period
}
$Cert = New-SelfSignedCertificate @newCert

# Export public key only
New-Item -Path "C:\Temp\OSD\Certs" -ItemType Directory -Force | Out-Null
$certFolder = "C:\Temp\OSD\Certs"
$certExport = @{
    Cert     = $Cert
    FilePath = "$($certFolder)\$($subjectName).cer"
}
Export-Certificate @certExport

# Export with private key
$certThumbprint = $Cert.Thumbprint
$certPassword = ConvertTo-SecureString -String "@H1ghS3curePassw0rd!" -Force -AsPlainText

$pfxExport = @{
    Cert         = "Cert:\LocalMachine\My\$($certThumbprint)"
    FilePath     = "$($certFolder)\$($subjectName).pfx"
    ChainOption  = "EndEntityCertOnly"
    NoProperties = $null
    Password     = $certPassword
}
Export-PfxCertificate @pfxExport






$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Import-Certificate.log"
Start-Transcript -Path (Join-Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" $Global:Transcript) -ErrorAction Ignore

Write-Host -ForegroundColor Cyan "Importing PFX certificate"
$subjectName = "OSDCloudRegistration"
$certPassword = ConvertTo-SecureString -String "@H1ghS3curePassw0rd!" -Force -AsPlainText

$Params = @()
$Params = @{
    FilePath          = "$env:SystemDrive\OSDCloud\Scripts\$($subjectName).pfx"
    CertStoreLocation = "Cert:\LocalMachine\My"
    Password          = $certPassword
}
Import-PfxCertificate @Params | Out-Null

Write-Host -ForegroundColor Cyan "Remove cert"
Remove-Item $env:SystemDrive\OSDCloud\Scripts\$($subjectName).pfx -Force

Stop-Transcript