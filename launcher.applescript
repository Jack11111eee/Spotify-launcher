-- 启动器 App 的全部逻辑都在包内的 launcher.sh 里，这里只负责调用它。
-- launcher.sh 自己会弹窗提示错误，所以这里不再重复弹窗，只把信息记进日志。

set launcherPath to (POSIX path of (path to me)) & "Contents/Resources/launcher.sh"
set logPath to (POSIX path of (path to home folder)) & "Library/Logs/SpotifyLauncher.log"

try
	do shell script quoted form of launcherPath & " 2>>" & quoted form of logPath
on error errMsg
	do shell script "echo " & quoted form of ("[" & (current date) & "] " & errMsg) & " >> " & quoted form of logPath
end try