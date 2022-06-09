Function Invoke-CertStream {
    <# 
    .SYNOPSIS
    Powershell certstream.calidog.io client

    .DESCRIPTION
    Interact with CertStream network to monitor an aggregated feed from a collection of Certificate Transparency Logs.


    .PARAMETER Filter
    Filter only matching names

    .PARAMETER URL
    URL of CertStream Web Socket endpoint, default https://certstream.calidog.io/

    .EXAMPLE
    Invoke-CertStream 
    Get entire stream

    .EXAMPLE
    Invoke-CertStream -Filter "\.pl$"
    Displays only names from Poland

    .EXAMPLE
    Invoke-CertStream -Filter "\.pl$" | ForEach-Object { "Got $_" }
    Catch names from Poland and pipe them to further scriptblock

    .NOTES
    By Pawel Maziarz, for aptm.in/forge#powershell
    #>    
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Filter,
        [string]
        $URL = 'wss://certstream.calidog.io'
    )

    $ct = [Threading.CancellationToken]::new($false)
    $buffer = [Net.WebSockets.WebSocket]::CreateClientBuffer(1024, 1024)

    function wsConnect() {
        Write-Verbose "[$(Get-Date)] Connecting to $URL"
        do {
            $ws = [System.Net.WebSockets.ClientWebSocket]::new()
            $ws.Options.KeepAliveInterval = 0
            $conn = $ws.ConnectAsync($URL, $ct)
            While (!$conn.IsCompleted) { 
                Start-Sleep -Milliseconds 100 
            }
        } until ($ws.State -eq [Net.WebSockets.WebSocketState]::Open)
        Write-Verbose "[$(Get-Date)] Connected to $URL"
        return $ws
    }

    do {
        $ws = wsConnect
        try {  
            while ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
                $data = ""
                do {
                    $result = $ws.ReceiveAsync($buffer, $ct)
                    $data += [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Result.Count)
                } until (
                    $ws.State -ne [Net.WebSockets.WebSocketState]::Open -or $result.Result.EndOfMessage
                )
     
                if (-not [string]::IsNullOrEmpty($data) -and $result.Result.EndOfMessage) {
                    $json = $data | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($json.message_type -eq "certificate_update") {
                        $json.data.leaf_cert.all_domains -match $Filter
                    }
                }
            }
        }
        catch {
            Write-Verbose "[$(Get-Date)] Exception: $_"
        }
        finally {
            Write-Verbose "[$(Get-Date)] WebSocket closed"
            $ws.Dispose()
        }
    } while ($true)
}