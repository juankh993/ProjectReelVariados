Add-Type -AssemblyName PresentationFramework

$msg = @"
Datoneta - recordatorio

Hoy toca reautorizar el token para ver las metricas.

1) En Google Cloud, habilitar la "YouTube Analytics API".
2) Correr:

scripts\youtube-auth.ps1 -Canal variado -Scope "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/yt-analytics.readonly"

3) Despues:

scripts\metricas-youtube.ps1 -Dias 28 -Max 10 -Guardar

Ver docs\METRICAS.md
"@

[System.Windows.MessageBox]::Show($msg, "Recordatorio Datoneta") | Out-Null
