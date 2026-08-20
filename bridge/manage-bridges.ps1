# manage-bridges.ps1 — Start, stop, and manage all OmniRoute bridges
# Usage:
#   .\manage-bridges.ps1 start          # Start all bridges
#   .\manage-bridges.ps1 stop           # Stop all bridges
#   .\manage-bridges.ps1 status         # Check status of all bridges
#   .\manage-bridges.ps1 start meta     # Start only Meta bridge
#   .\manage-bridges.ps1 stop deepseek  # Stop only DeepSeek bridge

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop", "status", "restart")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "meta", "deepseek", "mimo", "gemini", "gemini-chat", "flow")]
    [string]$Bridge = "all"
)

$ErrorActionPreference = "Stop"

# Bridge definitions
$Bridges = @{
    "meta" = @{
        Name = "Meta Web Bridge"
        Port = 20136
        Script = "bridge\meta-web-bridge\bridge.mjs"
        HealthEndpoint = "/healthz"
    }
    "deepseek" = @{
        Name = "DeepSeek Web Bridge"
        Port = 20137
        Script = "bridge\deepseek-web-bridge\bridge.mjs"
        HealthEndpoint = "/healthz"
    }
    "mimo" = @{
        Name = "MiMo Web Bridge"
        Port = 20135
        Script = "bridge\mimo-web-bridge\bridge.mjs"
        HealthEndpoint = "/healthz"
    }
    "gemini" = @{
        Name = "Gemini Image Bridge"
        Port = 20133
        Script = "bridge\gemini-bridge\bridge.py"
        HealthEndpoint = "/health"
        Python = $true
    }
    "gemini-chat" = @{
        Name = "Gemini Chat Bridge"
        Port = 20138
        Script = "bridge\gemini-chat-bridge\bridge.mjs"
        HealthEndpoint = "/healthz"
    }
    "flow" = @{
        Name = "Flow Browser Bridge"
        Port = 20134
        Script = "bridge\flow-browser\flow-bridge.mjs"
        HealthEndpoint = "/health"
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Test-BridgeHealth {
    param([string]$Name, [hashtable]$Config)
    
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($Config.Port)$($Config.HealthEndpoint)" -TimeoutSec 2 -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        return $data.ok -eq $true
    } catch {
        return $false
    }
}

function Start-Bridge {
    param([string]$Name, [hashtable]$Config)
    
    Write-Log "Starting $($Config.Name) on port $($Config.Port)..."
    
    # Check if already running
    if (Test-BridgeHealth -Name $Name -Config $Config) {
        Write-Log "$($Config.Name) is already running" -Level "WARN"
        return $true
    }
    
    # Check if port is in use
    $portInUse = Get-NetTCPConnection -LocalPort $Config.Port -ErrorAction SilentlyContinue
    if ($portInUse) {
        Write-Log "Port $($Config.Port) is already in use" -Level "ERROR"
        return $false
    }
    
    # Start the bridge
    $scriptPath = Join-Path $PSScriptRoot $Config.Script
    if (-not (Test-Path $scriptPath)) {
        Write-Log "Script not found: $scriptPath" -Level "ERROR"
        return $false
    }
    
    try {
        if ($Config.Python) {
            # Python bridge
            $venvPath = Join-Path (Split-Path $scriptPath) ".venv\Scripts\python.exe"
            if (Test-Path $venvPath) {
                Start-Process -FilePath $venvPath -ArgumentList $scriptPath -NoNewWindow -PassThru | Out-Null
            } else {
                Start-Process -FilePath "python" -ArgumentList $scriptPath -NoNewWindow -PassThru | Out-Null
            }
        } else {
            # Node.js bridge
            Start-Process -FilePath "node" -ArgumentList $scriptPath -NoNewWindow -PassThru | Out-Null
        }
        
        # Wait for bridge to start
        $maxWait = 10
        $waited = 0
        while ($waited -lt $maxWait) {
            Start-Sleep -Seconds 1
            $waited++
            if (Test-BridgeHealth -Name $Name -Config $Config) {
                Write-Log "$($Config.Name) started successfully"
                return $true
            }
        }
        
        Write-Log "$($Config.Name) failed to start within ${maxWait}s" -Level "ERROR"
        return $false
    } catch {
        Write-Log "Failed to start $($Config.Name): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Stop-Bridge {
    param([string]$Name, [hashtable]$Config)
    
    Write-Log "Stopping $($Config.Name)..."
    
    try {
        # Find process using the port
        $connections = Get-NetTCPConnection -LocalPort $Config.Port -ErrorAction SilentlyContinue
        if ($connections) {
            $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            foreach ($pid in $pids) {
                $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($process) {
                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                    Write-Log "Stopped process $pid ($($process.ProcessName))"
                }
            }
            Write-Log "$($Config.Name) stopped"
        } else {
            Write-Log "$($Config.Name) is not running" -Level "WARN"
        }
    } catch {
        Write-Log "Failed to stop $($Config.Name): $($_.Exception.Message)" -Level "ERROR"
    }
}

function Get-BridgeStatus {
    param([string]$Name, [hashtable]$Config)
    
    $running = Test-BridgeHealth -Name $Name -Config $Config
    $status = if ($running) { "RUNNING" } else { "STOPPED" }
    $color = if ($running) { "Green" } else { "Red" }
    
    Write-Host "$($Config.Name) (port $($Config.Port)): " -NoNewline
    Write-Host $status -ForegroundColor $color
    
    return $running
}

# Main execution
Write-Log "Bridge Manager - Action: $Action, Bridge: $Bridge"

$bridgeNames = if ($Bridge -eq "all") { $Bridges.Keys } else { @($Bridge) }

switch ($Action) {
    "start" {
        $results = @{}
        foreach ($name in $bridgeNames) {
            $config = $Bridges[$name]
            if (-not $config) {
                Write-Log "Unknown bridge: $name" -Level "ERROR"
                continue
            }
            $results[$name] = Start-Bridge -Name $name -Config $config
        }
        
        Write-Log "Summary:"
        foreach ($name in $results.Keys) {
            $status = if ($results[$name]) { "OK" } else { "FAILED" }
            Write-Log "  $name : $status"
        }
    }
    
    "stop" {
        foreach ($name in $bridgeNames) {
            $config = $Bridges[$name]
            if (-not $config) {
                Write-Log "Unknown bridge: $name" -Level "ERROR"
                continue
            }
            Stop-Bridge -Name $name -Config $config
        }
    }
    
    "status" {
        Write-Log "Bridge Status:"
        foreach ($name in $bridgeNames) {
            $config = $Bridges[$name]
            if (-not $config) {
                Write-Log "Unknown bridge: $name" -Level "ERROR"
                continue
            }
            Get-BridgeStatus -Name $name -Config $config | Out-Null
        }
    }
    
    "restart" {
        foreach ($name in $bridgeNames) {
            $config = $Bridges[$name]
            if (-not $config) {
                Write-Log "Unknown bridge: $name" -Level "ERROR"
                continue
            }
            Stop-Bridge -Name $name -Config $config
            Start-Sleep -Seconds 2
            Start-Bridge -Name $name -Config $config
        }
    }
}

Write-Log "Done"
