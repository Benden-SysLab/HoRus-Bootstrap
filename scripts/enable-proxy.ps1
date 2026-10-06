$proxy = Get-Content .json\proxy.json -Raw | ConvertFrom-Json
$uri = "http://$($proxy.username):$([uri]::EscapeDataString($proxy.password))@$($proxy.ip):$($proxy.port)"
$env:HTTP_PROXY = $uri
$env:HTTPS_PROXY = $uri
$env:http_proxy = $uri
$env:https_proxy = $uri
$env:NO_PROXY = "192.0.2.0/24,198.51.100.0/24,192.0.2.1"
$env:no_proxy = $env:NO_PROXY
Write-Host "Terraform proxy enabled: $($proxy.ip):$($proxy.port)"
