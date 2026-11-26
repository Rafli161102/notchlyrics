$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Runtime.WindowsRuntime

$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]

function Await-WinRT($WinRtTask, $ResultType) {
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
  })[0].MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  return $netTask.Result
}

function Await-WinRTAction($WinRtTask) {
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
  })[0]
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
}

function Read-ArtworkBase64($MediaProps) {
  try {
    if ($null -eq $MediaProps.Thumbnail) { return "" }
    $stream = Await-WinRT ($MediaProps.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    $size = [int]$stream.Size
    if ($size -le 0 -or $size -gt 6291456) { return "" }
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    $loadOp = $reader.LoadAsync([uint32]$size)
    $null = Await-WinRT $loadOp ([uint32])
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    $reader.Dispose()
    $stream.Dispose()
    return "data:image/jpeg;base64," + [Convert]::ToBase64String($bytes)
  } catch {
    return ""
  }
}

$manager = Await-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$lastThumbKey = ""
$lastThumbData = ""

# Handle optional command mode: win_smtc.ps1 -Command toggle|next|previous
if ($args.Count -ge 1 -and $args[0] -in @("toggle", "next", "previous")) {
  $session = $manager.GetCurrentSession()
  if ($null -ne $session) {
    if ($args[0] -eq "toggle") { $null = Await-WinRT ($session.TryTogglePlayPauseAsync()) ([bool]) }
    elseif ($args[0] -eq "next") { $null = Await-WinRT ($session.TrySkipNextAsync()) ([bool]) }
    elseif ($args[0] -eq "previous") { $null = Await-WinRT ($session.TrySkipPreviousAsync()) ([bool]) }
  }
  exit 0
}

while ($true) {
  try {
    $session = $manager.GetCurrentSession()
    if ($null -eq $session) {
      Write-Output '{"playing":false,"title":"","artist":"","album":"","duration":0,"elapsed":0,"appId":"","artworkUrl":""}'
    } else {
      $props = Await-WinRT ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
      $playback = $session.GetPlaybackInfo()
      $timeline = $session.GetTimelineProperties()

      $playing = ($playback.PlaybackStatus -eq [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing)
      $duration = [Math]::Max(0, $timeline.EndTime.TotalSeconds - $timeline.StartTime.TotalSeconds)
      $rawPos = [Math]::Max(0, $timeline.Position.TotalSeconds - $timeline.StartTime.TotalSeconds)
      if ($playing -and $timeline.LastUpdatedTime.Year -gt 2000) {
        $drift = ([DateTimeOffset]::UtcNow - $timeline.LastUpdatedTime).TotalSeconds
        if ($drift -gt 0 -and $drift -lt 10) {
          $rawPos += $drift
        }
      }
      if ($duration -gt 0 -and $rawPos -gt $duration) { $rawPos = $duration }

      $thumbKey = "$($props.Title)|$($props.Artist)|$($props.AlbumTitle)"
      if ($thumbKey -ne $lastThumbKey) {
        $lastThumbKey = $thumbKey
        $lastThumbData = Read-ArtworkBase64 $props
      }

      $payload = @{
        playing = $playing
        title = [string]$props.Title
        artist = [string]$props.Artist
        album = [string]$props.AlbumTitle
        duration = [Math]::Round($duration, 2)
        elapsed = [Math]::Round($rawPos, 3)
        appId = [string]$session.SourceAppUserModelId
        artworkUrl = $lastThumbData
      } | ConvertTo-Json -Compress
      Write-Output $payload
    }
  } catch {
    Write-Output '{"playing":false,"title":"","artist":"","album":"","duration":0,"elapsed":0,"appId":"","artworkUrl":""}'
  }
  Start-Sleep -Milliseconds 250
}
