' Run the agent on Windows with no visible console window (background).
' Use with Task Scheduler or the Startup folder.
Set sh = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = scriptDir
sh.Run "pythonw.exe """ & scriptDir & "\agent.py""", 0, False
