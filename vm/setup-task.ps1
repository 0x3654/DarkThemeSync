$ErrorActionPreference = 'Continue'

# Текущая тема залогиненного пользователя (для контроля)
$cur = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -match 'S-1-5-21-' } | ForEach-Object {
    $p = $_.Name + '\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (Test-Path ('Registry::' + $p)) { (Get-ItemProperty ('Registry::' + $p)).AppsUseLightTheme }
}
Write-Output ("CURRENT=" + ($cur -join ','))

# Основной скрипт: читает флаг от мака и перекрашивает тему пользователя
$ps1 = @'
$mode = Get-Content 'C:\Users\Public\mac_theme.txt' -ErrorAction SilentlyContinue
$v = if ($mode -match 'dark') { 0 } else { 1 }
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $k -Force | Out-Null
Set-ItemProperty -Path $k -Name AppsUseLightTheme -Value $v -Type DWord
Set-ItemProperty -Path $k -Name SystemUsesLightTheme -Value $v -Type DWord
$sig = '[DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);'
$t = Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace Win32 -PassThru
$r = [IntPtr]::Zero
[void]$t::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
'@
Set-Content -Path 'C:\Users\Public\MacThemeSync.ps1' -Value $ps1 -Encoding ASCII

# VBS-обёртка, чтобы окно PowerShell не мигало при каждом переключении
$vbs = "CreateObject(""Wscript.Shell"").Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\MacThemeSync.ps1"", 0, False" + [char]13 + [char]10
Set-Content -Path 'C:\Users\Public\MacThemeSync.vbs' -Value $vbs -Encoding ASCII

# прибрать старые файлы из C:\Windows\Temp (не читались пользователем)
Remove-Item 'C:\Windows\Temp\MacThemeSync.ps1','C:\Windows\Temp\MacThemeSync.vbs','C:\Windows\Temp\mac_theme.txt','C:\Windows\Temp\p.b64','C:\Windows\Temp\setup.ps1' -ErrorAction SilentlyContinue

$u = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $u) { $u = 'm' }
Write-Output ("USER=" + $u)

schtasks.exe /Create /F /TN MacThemeSync /TR 'wscript.exe C:\Users\Public\MacThemeSync.vbs' /SC ONCE /ST 23:59 /RU $u /IT

Write-Output "SETUP_DONE"
