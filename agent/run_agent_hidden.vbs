' تشغيل الـ Agent على ويندوز بدون نافذة سوداء ظاهرة (في الخلفية).
' استخدمه مع Task Scheduler أو مجلد Startup.
Set sh = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = scriptDir
sh.Run "pythonw.exe """ & scriptDir & "\agent.py""", 0, False
