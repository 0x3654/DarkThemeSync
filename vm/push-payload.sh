#!/bin/bash
# Заливает /tmp/pd-theme-setup.ps1 в VM (C:\Windows\Temp\setup.ps1) по кускам и запускает.
VM="Windows 11"
SRC="/tmp/pd-theme-setup.ps1"

B64=$(base64 -i "$SRC" | tr -d '\n')
len=${#B64}
echo "payload b64 length: $len"

ok=0
for attempt in 1 2 3; do
  i=0; first=1
  while [ $i -lt $len ]; do
    chunk=${B64:$i:400}
    if [ $first -eq 1 ]; then
      CMD="Set-Content C:\\Windows\\Temp\\p.b64 '$chunk'"; first=0
    else
      CMD="Add-Content C:\\Windows\\Temp\\p.b64 '$chunk'"
    fi
    if ! prlctl exec "$VM" powershell -NoProfile -Command "$CMD" >/dev/null 2>&1; then
      echo "chunk $i: prlctl error, retry after pause"
      sleep 2
      prlctl exec "$VM" powershell -NoProfile -Command "$CMD" >/dev/null 2>&1 || true
    fi
    i=$((i+400))
    sleep 0.4
  done
  # длина без пробелов на стороне гостя
  RB=$(prlctl exec "$VM" powershell -NoProfile -Command "(([IO.File]::ReadAllText('C:\Windows\Temp\p.b64')) -replace '\s','').Length" 2>/dev/null | tr -d '\r\n ')
  echo "attempt $attempt: guest=$RB local=$len"
  if [ "$RB" = "$len" ]; then ok=1; break; fi
  sleep 1
done

if [ $ok -ne 1 ]; then echo "FAILED to transfer"; exit 1; fi

prlctl exec "$VM" powershell -NoProfile -Command "\$d=[IO.File]::ReadAllText('C:\Windows\Temp\p.b64') -replace '\s',''; [IO.File]::WriteAllText('C:\Windows\Temp\setup.ps1',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\$d))); & 'C:\Windows\Temp\setup.ps1'" 2>&1
