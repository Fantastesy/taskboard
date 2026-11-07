# Windows-Erinnerung fuer faellige Todos, eine Benachrichtigung pro Punkt.
# Aufruf: notify.ps1 "<id>~<Text>|<id>~<Text>"
# Knoepfe "Erledigt" / "In 15 Min" oeffnen taskboard:done/<id> bzw. taskboard:snooze/<id> -> toast-action.vbs -> todo.lua
param([string]$Text)
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null

$esc = [Security.SecurityElement]
$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)

foreach ($item in ($Text -split '\|')) {
    $id, $name = $item -split '~', 2
    if (-not $name -or $id -notmatch '^\d+$') { continue }
    $name = $esc::Escape($name.Trim())
    # scenario=reminder: bleibt stehen, bis man einen Knopf klickt
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml(@"
<toast scenario="reminder">
  <visual><binding template="ToastGeneric"><text>Todo fällig</text><text>$name</text></binding></visual>
  <actions>
    <action content="Erledigt" activationType="protocol" arguments="taskboard:done/$id"/>
    <action content="In 15 Min nochmal" activationType="protocol" arguments="taskboard:snooze/$id"/>
    <action content="Schließen" activationType="system" arguments="dismiss"/>
  </actions>
</toast>
"@)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $toast.Tag = "todo$id"
    $notifier.Show($toast)
}
