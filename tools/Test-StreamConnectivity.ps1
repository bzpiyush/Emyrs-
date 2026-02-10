<#
.SYNOPSIS
    Stream ping - Continuous TCP connectivity test with real-time output.
    Run this script FROM INSIDE an Azure VM (via RDP) to test connectivity to another VM's private IP.

.DESCRIPTION
    This script performs continuous TCP "stream ping" to prove zero packet loss during 
    Merlin migration. Uses TCP (not ICMP) so it works regardless of firewall/NSG ICMP rules.
    
    Output streams in real-time like traditional ping but uses TCP connections.

.PARAMETER TargetIP
    The private IP address of the target VM to test connectivity to.

.PARAMETER Port
    The TCP port to test. Default is 3389 (RDP) which is typically open.

.PARAMETER Count
    Number of pings. Default is 0 (continuous until Ctrl+C). Use -Count 100 for 100 pings.

.PARAMETER IntervalMs
    Milliseconds between each ping. Default is 500 (2 pings per second).

.PARAMETER TimeoutMs
    Connection timeout in milliseconds. Default is 2000 (2 seconds).

.EXAMPLE
    .\Test-StreamConnectivity.ps1 -TargetIP "10.0.0.5"
    Continuous stream ping to 10.0.0.5:3389 until Ctrl+C.

.EXAMPLE
    .\Test-StreamConnectivity.ps1 -TargetIP "10.0.0.5" -Count 100
    Send 100 TCP pings then show summary.

.EXAMPLE
    .\Test-StreamConnectivity.ps1 -TargetIP "10.0.0.5" -Port 445 -IntervalMs 200
    Fast stream ping (5/sec) to SMB port.

.NOTES
    Author: Emyrs (Merlin Migration Assistant)
    Use Case: Run BEFORE and DURING migration to prove zero packet loss
    Press Ctrl+C to stop and see summary statistics
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetIP,

    [Parameter(Mandatory = $false)]
    [int]$Port = 3389,

    [Parameter(Mandatory = $false)]
    [int]$Count = 0,

    [Parameter(Mandatory = $false)]
    [int]$IntervalMs = 500,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutMs = 2000
)

# Results tracking
$script:seq = 0
$script:successCount = 0
$script:failCount = 0
$script:latencies = @()
$script:startTime = Get-Date

# Cleanup handler for Ctrl+C
$script:running = $true

function Show-Summary {
    $endTime = Get-Date
    $duration = ($endTime - $script:startTime).TotalSeconds
    $total = $script:successCount + $script:failCount
    $lossPercent = if ($total -gt 0) { [math]::Round(($script:failCount / $total) * 100, 1) } else { 0 }
    
    $avgLatency = if ($script:latencies.Count -gt 0) { [math]::Round(($script:latencies | Measure-Object -Average).Average, 1) } else { 0 }
    $minLatency = if ($script:latencies.Count -gt 0) { ($script:latencies | Measure-Object -Minimum).Minimum } else { 0 }
    $maxLatency = if ($script:latencies.Count -gt 0) { ($script:latencies | Measure-Object -Maximum).Maximum } else { 0 }

    Write-Host ""
    Write-Host "--- $TargetIP`:$Port TCP ping statistics ---" -ForegroundColor Cyan
    Write-Host "$total packets transmitted, $($script:successCount) received, $lossPercent% packet loss, time $([math]::Round($duration, 1))s"
    
    if ($script:latencies.Count -gt 0) {
        Write-Host "rtt min/avg/max = $minLatency/$avgLatency/$maxLatency ms"
    }
    
    if ($script:failCount -eq 0) {
        Write-Host "Result: ZERO PACKET LOSS" -ForegroundColor Green
    } else {
        Write-Host "Result: $($script:failCount) PACKETS DROPPED" -ForegroundColor Red
    }
}

# Register Ctrl+C handler
[Console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Show-Summary }

# Banner
Write-Host ""
Write-Host "TCPING $TargetIP`:$Port - Press Ctrl+C to stop" -ForegroundColor Cyan
Write-Host ""

try {
    while ($script:running) {
        $script:seq++
        
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Async connect with timeout
            $asyncResult = $tcpClient.BeginConnect($TargetIP, $Port, $null, $null)
            $connected = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            
            if ($connected -and $tcpClient.Connected) {
                $tcpClient.EndConnect($asyncResult)
                $stopwatch.Stop()
                $latency = $stopwatch.ElapsedMilliseconds
                $script:latencies += $latency
                $script:successCount++
                
                Write-Host "Reply from $TargetIP`:$Port seq=$($script:seq) time=${latency}ms" -ForegroundColor Green
            } else {
                $stopwatch.Stop()
                $script:failCount++
                Write-Host "Request timeout for seq=$($script:seq)" -ForegroundColor Red
            }
            
            $tcpClient.Close()
            $tcpClient.Dispose()
        }
        catch {
            $script:failCount++
            Write-Host "Request failed for seq=$($script:seq) - $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Check if we've reached count limit
        if ($Count -gt 0 -and $script:seq -ge $Count) {
            break
        }
        
        Start-Sleep -Milliseconds $IntervalMs
    }
}
finally {
    Show-Summary
}
