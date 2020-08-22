Write-Host "Server Starting"
$Global:store = [Hashtable]::Synchronized(@{})
$store.Host = $Host
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8081/")
$listener.Start()

$sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()

$MaxThreads = 5
$global:RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionstate, $Host)
$global:RunspacePool.Open()
# $global:RunspacePool.SessionStateProxy.SetVariable("store", $store)

$global:Jobs = @()

# $Runspace = [runspacefactory]::CreateRunspace()
# $PowerShell = [powershell]::Create()
# $PowerShell.Runspace = $Runspace
# $Runspace.Open()

$global:syncHandler = {
  param( $listener, $store)
  try {
    Write-Output "Sync Handler3"
    Write-Host "Sync Handler 2"
    $currInd = $global:Jobs.Length
    Write-Output $currInd
    Write-Host $currInd
    $Context = $listener.GetContext()
    Write-Output "Before gen event"
    Write-Host "Before gen event"
    $store.Host.Runspace.Events.GenerateEvent( "RequestRecieved", "paramSender", "paramArgs", "paramData")
    #         $PowerShell3 = [powershell]::Create()
    # $PowerShell3.RunspacePool = $global:RunspacePool  
    # $PowerShell3.AddScript( $global:syncHandler).AddArgument($listener)
    # Write-Output "After Add Script"
    # $global:Jobs += $PowerShell3.BeginInvoke()
    
    Write-Output "After Context"
    Write-Host "After Context"
    # Get-PSDrive
    $URL = $Context.Request.Url.LocalPath
    New-PSDrive -Name MyPowerShellSite -Scope "Global" -PSProvider FileSystem -Root "$($PWD.Path)\test-root"  
    $Context.Response.ContentType = [System.Web.MimeMapping]::GetMimeMapping("MyPowerShellSite:$URL")

    # $Content = Get-Content -Encoding Byte -Path "MyPowerShellSite:$URL"
    # $Context.Response.OutputStream.Write($Content, 0, $Content.Length)

    # $fileStream = New-Object IO.FileStream "MyPowerShellSite:$URL" , 'Open'
    $fileStream = [System.IO.File]::OpenRead( (Convert-Path -LiteralPath "MyPowerShellSite:$URL"))
    $fileStream.CopyTo($Context.Response.OutputStream);
    $fileStream.Close()

    $Context.Response.Close()
    Write-Output "Added new Job"
    Write-Host "Added new Job"
    $currInd = $global:Jobs.Length
    Write-Output $currInd
    Write-Host $currInd
  }
  catch {
    Write-Host "An error occurred:"
    Write-Output $_.ScriptStackTrace
    Write-Host $_.ScriptStackTrace
    $_
  }
}


# $asyncHandler = [AsyncCallback] {
#   param( $result)
#   Write-Host "Into Async Handler"
#   $listener = $result.AsyncState;
#   $Context = $listener.EndGetContext($result);
#   Write-Host "Async Context End Handler"
#   $URL = $Context.Request.Url.LocalPath
#   $Content = Get-Content -Encoding Byte -Path "MyPowerShellSite:$URL"
#   $Context.Response.ContentType = [System.Web.MimeMapping]::GetMimeMapping("MyPowerShellSite:$URL")
#   $Context.Response.OutputStream.Write($Content, 0, $Content.Length)
#   $Context.Response.Close()
# }


try {
  # &$global:syncHandler $listener

  # $listener.BeginGetContext($asyncHandler, $listener)

  # $syncJob = Start-Job -ScriptBlock $global:syncHandler -Name "syncBlock" -ArgumentList $listener

  # $PowerShell.AddScript( $global:syncHandler).AddArgument($listener).AddArgument($PowerShell)
  # $job = $PowerShell.BeginInvoke()

  $PowerShell = [powershell]::Create()
  $PowerShell.RunspacePool = $global:RunspacePool  
  $PowerShell.AddScript( $global:syncHandler).AddArgument($listener).AddArgument($store)
  $global:Jobs += $PowerShell.BeginInvoke()
  Write-Host "Before Event reg"
  Register-EngineEvent -SourceIdentifier "RequestRecieved" -Action {
    Write-Host "Event called"
    Write-Host $Event
    Write-Host $EventSubscriber
    Write-Host $Sender
    Write-Host $EventArgs
    Write-Host $Args
    $PowerShell2 = [powershell]::Create()
    $PowerShell2.RunspacePool = $global:RunspacePool  
    $PowerShell2.AddScript( $global:syncHandler).AddArgument($listener).AddArgument($store)
    Write-Output "After Add Script"
    $global:Jobs += $PowerShell2.BeginInvoke()    
  }    
  Write-Host "After Event reg"
  #     $PowerShell2 = [powershell]::Create()
  # $PowerShell2.RunspacePool = $global:RunspacePool  
  # $PowerShell2.AddScript( $global:syncHandler).AddArgument($listener)
  # Write-Output "After Add Script"
  # $global:Jobs += $PowerShell2.BeginInvoke()

  $res = $PowerShell.EndInvoke($global:Jobs[0])
  $PowerShell.dispose()
  Write-Host $res

  #     $res = $PowerShell2.EndInvoke($global:Jobs[1])
  # $PowerShell2.dispose()
  # Write-Host $res

  Write-Host "Waiting.."
  # while ($true) {
  #   Start-Sleep -Milliseconds 100
  #   # Receive-Job -Job $syncJob
  # } 
  # while ($global:Jobs.IsCompleted -contains $false) {
  #   Start-Sleep 1
  # }
  while ($true) {
    # $global:Jobs | Foreach-Object {
    #   $res = $PowerShell.EndInvoke($_)
    #   $PowerShell.dispose()
    #   Write-Host $res
      
    # }
  }

  Write-Host "Waiting End"
}
catch {
  Write-Host "An error occurred:"
  Write-Host $_.ScriptStackTrace
}
finally {
  try {
    Write-Host "Final block"
    # Remove-PSDrive -Name MyPowerShellSite
    $currInd = $global:Jobs.Length
    Write-Host $currInd
    # $global:Jobs | Foreach-Object {
    #   $res = $PowerShell.EndInvoke($_)
    #   $PowerShell.dispose()
    #   Write-Host $res
    # }
    # $Runspace.Close()
    $global:RunspacePool.Close()
    $listener.Stop()
    $listener.Close()
    # $batch = Get-Job -Name syncBlock
    # $batch | Remove-Job
    Write-Host "Final Done"
  }
  catch {
    Write-Host "Final Error"
    Write-Host $_
    Write-Host $_.ScriptStackTrace
  }
}
