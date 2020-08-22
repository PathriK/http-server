using namespace System.Management.Automation
using namespace System.Management.Automation.Runspaces

$DebugPreference = 'Continue'
$InformationPreference = 'Continue'
$port = "8081"
$MaxThreads = 5
$message404 = "404 This is not the page you're looking for.";

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

Write-Information "Server Starting"
$listener.Start()
$isServerRunning = $true

$sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('DebugPreference', $DebugPreference, $null))
)

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('InformationPreference', $InformationPreference, $null))
)

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('listener', $listener, $null))
)

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('parentHost', $Host, $null))
)

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('message404', $message404, $null))
)

$sessionstate.Variables.Add(
  (New-Object SessionStateVariableEntry('isServerRunning', $isServerRunning, $null))
)

$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionstate, $Host)
$RunspacePool.Open()

$Jobs = @{}
$currThreadID = 0

$requestHandler = {
  param( $currInd)
  try {
    Write-Debug "Inside Request Handler::$currInd"
    New-PSDrive -Name MyPowerShellSite -PSProvider FileSystem -Root "$($PWD.Path)\test-root" | Out-Null
    $Context = $listener.GetContext()
    Write-Debug "Before gen event::$currInd"
    [void]$parentHost.Runspace.Events.GenerateEvent( "RequestRecieved", $currInd, "", "")

    $URL = $Context.Request.Url.LocalPath
    Write-Information "Handling request for $URL - Thread::$currInd"
    if ($URL -eq "" -or $URL -eq "/") {
      $URL = "index.html"
    }

    $filePath = Convert-Path -LiteralPath "MyPowerShellSite:$URL"
    $response = $Context.Response
    if ($filePath -AND ([System.IO.File]::Exists($filePath))) {
      $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($filePath)
      Write-Debug "Reading file $filePath and responding::$currInd"
      Write-Information "Responding with 200 - Thread::$currInd"
      $fileStream = [System.IO.File]::OpenRead( $filePath)
      $fileStream.CopyTo($response.OutputStream);
      $fileStream.Close()
      $response.Close()
      Write-Debug "Response sent::$currInd"
    }
    else {
      Write-Debug "Responding 404 for $filePath::$currInd"
      Write-Information "Responding with 400 - Thread::$currInd"
      $response.StatusCode = 404;
      $response.ContentType = 'text/html' ;
      [byte[]]$buffer = [System.Text.Encoding]::UTF8.GetBytes($message404)
      $response.ContentLength64 = $buffer.length
      $output = $response.OutputStream
      $output.Write($buffer, 0, $buffer.length)
      $output.Close()
    }
  }
  catch {
    if ($isServerRunning) {
      Write-Debug "An error occurred::$currInd::"
      Write-Debug $_
      Write-Information "Error Occurred"
    }
  }
  finally {
    Write-Debug "Thread cleanup $currInd"
    Remove-PSDrive -Name MyPowerShellSite
  }
}

try {
  $PowerShell = [powershell]::Create()
  $PowerShell.RunspacePool = $RunspacePool
  $Id = $currThreadID++
  [void]$PowerShell.AddScript( $requestHandler).AddArgument($Id)
  Write-Debug "Starting Thread $Id"
  $Jobs.Add($Id, ([PSCustomObject]@{
        PowerShell = $PowerShell
        isRunning  = $true
        canEnd     = $false
        Handle     = $PowerShell.BeginInvoke()
      }))
  Write-Debug "Before Event reg"
  Register-EngineEvent -SourceIdentifier "RequestRecieved" -Action {
    $runningID = $Sender
    $PowerShell = [powershell]::Create()
    $PowerShell.RunspacePool = $RunspacePool
    $Id = $currThreadID++
    $PowerShell.AddScript( $requestHandler).AddArgument($Id)
    Write-Debug "Starting Thread $Id"
    $Jobs.Add($Id, ([PSCustomObject]@{
          PowerShell = $PowerShell
          isRunning  = $true
          canEnd     = $false
          Handle     = $PowerShell.BeginInvoke()
        }))
    Write-Debug "Marking thread $runningID for closure"
    $Jobs[$runningID].canEnd = $true
  } | Out-Null
  Write-Debug "Waiting.."
  Write-Information "Server Running..."
  while ($true) {
    $completedJobs = @()
    $Jobs.GetEnumerator() | ForEach-Object {
      $endJob = $_.Value
      $Id = $_.Key
      if ($endJob.Handle.IsCompleted) {
        Write-Debug "Ending thread $Id"
        Write-Host $endJob.PowerShell.EndInvoke($endJob.Handle)
        $endJob.PowerShell.dispose()
        $endJob.isRunning = $false
        $completedJobs += $_.Key
      }
    }
    $completedJobs | ForEach-Object {
      $Jobs.Remove($_)
    }

    Start-Sleep -Seconds 1
  }
  Write-Debug "Waiting End"
}
catch {
  Write-Debug "Main Thread Error::"
  Write-Host $_
  Write-Information "Error Occurred"
}
finally {
  try {
    Write-Debug "Final block"
    $isServerRunning = $false
    Unregister-Event -SourceIdentifier "RequestRecieved"
    $listener.Stop()
    $listener.Close()
    $Jobs.GetEnumerator() | ForEach-Object {
      $endJob = $_.Value
      $Id = $_.Key
      if ($endJob.Handle.IsCompleted) {
        Write-Debug "Trying to Stop thread:: $Id"
        Write-Host $endJob.PowerShell.EndInvoke($endJob.Handle)
        $endJob.PowerShell.dispose()
        $endJob.isRunning = $false
      }
      if (-NOT $endJob.Handle.IsCompleted) {
        Write-Debug "Force Stopping thread:: $Id"
        $endJob.PowerShell.Stop()
        $endJob.PowerShell.dispose()
        $endJob.isRunning = $false
      }
    }
    $RunspacePool.Dispose()
    $RunspacePool.Close()
    Write-Information "Server Stopped"
  }
  catch {
    Write-Debug "Final Error::"
    Write-Host $_
    Write-Information "Server Stopped with Error"
  }
}
