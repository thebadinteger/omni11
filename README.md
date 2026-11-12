# omni11  
### harmless windows 11 tweaker and debloater

modes:
- patch an iso before install
- clean a live windows install
---
## run  
```powershell
irm https://raw.githubusercontent.com/thebadinteger/omni11/refs/heads/main/omni11.ps1 | iex
```
(would ask for admin)  

## menu
```
[omni11] no harm
[1] postsetup tweaks
[2] patch .iso
[0] exit
```
- `1` - clean the running windows installation
- `2` - patch a Windows 11 iso
- `0` - exit the script

## step prompts
```
[y] yes, do it
[n] no, skip it
[a] do it all (recommended)
```
just a legend. every step asks on its own
- enter or `y` = run this step
- `n` = skip this step
- `a` = run this step and all remaining steps without asking (if you know or don't know what you doing)

1. critical steps (mount, copy, export, unmount) abort the whole flow on error
2. non-critical steps report the error and continue

## requirements
iso patch:
- windows 11 host
- admin rights
- about 20 gb free on the work dir drive
- x64 windows iso with `sources\boot.wim` and `sources\install.wim` or `install.esd`
- no split wim (`install*.swm`) for the iso patcher
- `autounattend.xml` and `oscdimg.exe` in the script dir or `%TEMP%\omni11`, or internet to download them from the omni11 repo

postsetup:
- windows 11 host
- admin rights

## paths
| path | what |
| --- | --- |
| `C:\omni11` | iso contents copy and dism work dir |
| `C:\scratchdir` | dism mount dir |
| `%TEMP%\omni11` | cached `autounattend.xml` and `oscdimg.exe` |
| `%TEMP%` | fallback asset lookup |
| next to source iso | output `<iso-name>-omni11.iso` |

`autounattend.xml` is looked up in `%TEMP%\omni11`, then `%TEMP%`
`oscdimg.exe` is looked up in the script dir, cwd, `%TEMP%\omni11`, then `%TEMP%`
missing assets are downloaded from the omni11 repo
downloaded files are unblocked

## iso patcher
1. remove bloatware
2. remove inbox apps
3. remove edge (keeps webview intact)
4. clean image
5. remove legacy features
6. remove onedrive
7. load registry
8. patch system requirements
9. disable reserved storage
10. remove teams and sponsored apps
11. enable classic context menu
12. enable oobe local accounts
13. tweak chat icon
14. enable onedrive tweaks
15. edge reinstall block
16. remove telemetry
17. remove copilot and recall
18. privacy extra tweaks
19. disable powershell telemetry
20. disable ads and suggestions
21. disable ai extras
22. delivery and device tweaks
23. disable game dvr
24. disable sticky keys
25. disable services
26. disable telemetry tasks
27. clean shortcuts
28. patch boot requirements
29. copy autounattend

## postsetup
1. disable telemetry
2. defender samples
3. disable bloat and sponsored
4. stop bloatware processes
5. remove bloatware apps
6. clean bloatware shortcuts
7. remove inbox apps
8. remove edge
9. remove onedrive
10. clean components
11. remove legacy features
12. remove legacy features 2
13. disable bing search
14. disable ai features
15. privacy extras
16. powershell telemetry
17. ads and suggestions
18. delivery and device
19. disable bloat autostart
20. clean onedrive
21. block edge reinstall
22. disable hardware notifications
23. reserved storage
24. disable tracking
25. services
26. telemetry tasks
27. restore classic context menu
28. disable game dvr
29. disable update auto reboot
30. disable sticky keys popup
31. restart explorer

## bloat list
`$Bloat` is a pattern list. both iso and postsetup use it.
```
Clipchamp.Clipchamp
Microsoft.BingNews
Microsoft.BingWeather
Microsoft.BingSearch
Microsoft.Getstarted
Microsoft.MicrosoftOfficeHub
Microsoft.MicrosoftSolitaireCollection
Microsoft.Solitaire
Microsoft.OutlookForWindows
Microsoft.Outlook
Microsoft.LinkedIn
Microsoft.LinkedInforWindows
Microsoft.People
Microsoft.PowerAutomateDesktop
Microsoft.Todos
Microsoft.windowscommunicationsapps
Microsoft.WindowsFeedbackHub
Microsoft.WindowsMaps
Microsoft.YourPhone
Microsoft.ZuneVideo
MicrosoftCorporationII.MicrosoftFamily
MicrosoftCorporationII.QuickAssist
MicrosoftTeams
MSTeams
Microsoft.Copilot
Microsoft.MicrosoftStickyNotes
MicrosoftWindows.Client.WebExperience
MicrosoftWindows.CrossDevice
Microsoft.Windows.DevHome
Microsoft.StartExperiencesApp
Microsoft.WidgetsPlatformRuntime
```

## shared tweaks
these functions are used by both modes:
- `Invoke-PrivacyExtras` — telemetry, advertising id, speech privacy, input collection, activity feed, error reporting, cloud clipboard
- `Invoke-UiExtras` — consumer content, suggestions, spotlight, bing search, widgets
- `Invoke-AiExtras` — ai data analysis, notepad rewrite, paint cocreator
- `Invoke-DevicePerf` — delivery optimization, device metadata, update reboot, wpbt
- `Invoke-GameDvr` — game dvr and capture
- `Invoke-StickyKeys` — sticky/filter/toggle key popups
- `Invoke-ServicesList` — service disable list
- `Invoke-TasksList` — scheduled task removal list
- `Invoke-LegacyFeatures` — wmp, recall, fax, work folders
- `Invoke-LegacyFeatures2` — steps recorder, wordpad
- `Invoke-InboxApps` — inbox payload removal
- `Invoke-Shortcuts` — bloat shortcut removal
- `Invoke-EdgeRemove` — online edge uninstall
- `Invoke-OneDriveRemove` — online onedrive uninstall
- `Invoke-ComponentCleanup` — dism component cleanup
- `Invoke-PowerShellTelemetry` — powershell telemetry opt out

offline vs online is handled by `Use-OfflineMode`, `Use-OfflineReg` and `Use-OnlineReg`
`Set-Tweak` maps logical roots to the right hives:
- `SOFTWARE` -> `HKLM\SOFTWARE` or `HKLM\zSOFTWARE`
- `SYSTEM` -> `HKLM\SYSTEM` or `HKLM\zSYSTEM`
- `NTUSER` -> `HKCU` or `HKLM\zNTUSER`
- `DEFAULT` -> `HKCU` or `HKLM\zDEFAULT`

## troubleshooting

`[-] no admin get lost`
uac was denied or elevation failed

`[-] download failed: ...`
could not download `autounattend.xml` or `oscdimg.exe`
check network or put the file into `%TEMP%\omni11`

`[!] free space error...`
not enough space for the iso work dir
change `$MinFreeGb` or free space on the drive

`[!] split wim not supported`
iso uses `install.swm` instead of `install.wim`
script does not support split wims

`[-] no such index`
entered install index does not exist

`[!] dism failed ...`
dism rejected the operation
check the step output and the image state

`[!] oscdimg failed`
oscdimg returned non zero
check `%TEMP%\omni11\oscdimg.exe` and free space

leftover mounts:
```powershell
dism /cleanup-wim
Dismount-DiskImage -ImagePath 'D:\path\to\image.iso'
```

skipped vs failed:
- `[*] step skipped` means you answered `n`
- `[!] step error` means the step failed, read the message

## license
[badinteger](https://github.com/thebadinteger) - MIT

thanks:
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [MarkAdderly/MakuTweaker](https://github.com/MarkAdderly/MakuTweaker)
- [nano11-dev/nano11builder](https://github.com/nano11-dev/nano11builder)
