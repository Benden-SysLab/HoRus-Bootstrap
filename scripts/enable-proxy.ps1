$proxy = Get-Content .json\proxy.json -Raw | ConvertFrom-Json
$uri = "http://$($proxy.username):$([uri]::EscapeDataString($proxy.password))@$($proxy.ip):$($proxy.port)"
$env:HTTP_PROXY = $uri
$env:HTTPS_PROXY = $uri
$env:http_proxy = $uri
$env:https_proxy = $uri
Write-Host "Terraform proxy enabled: $($proxy.ip):$($proxy.port)"
