# Spotify 代理启动器

用 CEF 命令行参数启动 Spotify，让 Spotify 的流量走本地 Clash 代理 —— **不需要开 TUN 模式，也不占用 macOS 系统代理**。浏览器等其他 App 完全不受影响。

核心就是这一行：

```bash
open -a Spotify --args --proxy-server=http://127.0.0.1:59062
```

难点在于参数只在启动时生效，任何一次绕过启动器直接点 Spotify 图标，代理就失效了。这个启动器负责保证每次都是带参数启动。

## 构建

```bash
./build.sh              # 生成到 /Applications
./build.sh ~/Applications   # 或指定目录
```

生成 `/Applications/Spotify (代理).app`。目标目录不存在或不可写时，会自动改装到 `~/Applications`。

App 由 `osacompile` 生成后再拷入 `launcher.sh` 和图标，这会让 `osacompile` 的签名失效，所以构建的最后会重新做一次 ad-hoc 签名。不重签的话平时也能跑，但 App 一旦带上 quarantine 属性（AirDrop 过来、从压缩包解压）就会被 Gatekeeper 报成「已损坏」。

### 图标

图标由 `icon/make_icon.py` 生成，底图直接取自本机 Spotify 的真实图标，只在右下角加一枚绕行徽标。需要 python3 + Pillow。

```bash
python3 icon/make_icon.py     # 生成 icon/SpotifyProxy.icns
./build.sh                    # 构建时若发现没有图标，会自动生成一份
```

网格不是照抄模板，是量出来的：把 Spotify 图标的 alpha 通道和超椭圆做拟合，`n=5.0` 时 IoU 0.9952，图形主体 824/1024、四周留白 100px。徽标按档位单独调——大尺寸画得出绕行箭头，小尺寸留不住细节就退化成纯圆点，16px 干脆不加，因为那个尺寸下任何徽标都会糊成像是渲染瑕疵的黑点。

生成的 `.icns` 不会提交，也不该提交或分发：底图是 Spotify 的美术资源，把它（哪怕改过）放进公开仓库会有版权和商标问题。图标只在你自己的机器上、用你自己装的 Spotify 现生成现用。

## 使用

双击 `Spotify (代理).app` 即可，逻辑有五态：

| 当前状态 | 行为 |
|---|---|
| Spotify 没在运行 | 带代理参数启动 |
| 在运行，已带参数，代理通，也确实连着代理 | 只激活窗口，不重启 |
| 在运行，但没带参数（或端口变了） | 退出后用参数重启 |
| 在运行，已带参数，但代理不通 | 不重启（重启也连不上），提示先修好 Clash |
| 在运行，已带参数，代理也通，但没连着代理 | 退出后用参数重启 |

代理端口从 Clash Verge 配置动态读取（`~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml` 的 `verge_mixed_port`），以后改端口不用动启动器。

启动前会**通过代理真的发一次请求**（探 `apresolve.spotify.com`）。只看端口有没有人监听是不够的：节点挂掉的时候 mihomo 照样监听、照样接受连接，然后在往上连的时候才失败 —— 那种情况下 Spotify 完全连不上网，但端口探测是通的。

启动后还会回头确认参数真的带上了。因为 `open --args` 对**已经在运行**的实例是静默忽略的，如果只靠「发出去」而不确认「生效了」，就会出现「以为走了代理、其实没走」这种最糟的情况。

最后一条状态是给睡眠唤醒准备的：Mac 睡眠期间代理节点会短暂不可达，Spotify 走代理的连接断掉之后自己不会重建，表现就是**歌全部变灰**，而命令行参数看上去完全正常 —— 光看参数是看不出这种坏掉的。所以启动器会去查 Spotify 的网络子进程是不是真的还连着代理端口，没连着就重启一次。

> **首次重启 Spotify 时** macOS 会弹一次「"Spotify (代理)" 想要控制 "Spotify"」，需要点允许（系统设置 → 隐私与安全性 → 自动化）。
> 如果拒绝了这个授权，启动器就没法正常退出 Spotify，每次重启都会卡到超时兜底路径。

### 会弹窗的两种情况

- **代理不通，但 Spotify 没在运行**：会先问一句要不要继续。继续也能启动，只是 Spotify 完全连不上网，所以默认按钮是「取消」。
- **Spotify 在运行、参数也对，但代理不通**（第四态）：不重启（重启也连不上），直接提示先把 Clash Verge 弄通。

同一份提示在终端里跑时不会弹窗，而是打印到 stderr —— 启动器靠 `[ -t 1 ]` 判断自己是终端调用还是 App 调用。

也可以在终端直接跑，方便排查：

```bash
./launcher.sh
```

## 装好之后要做的两件事

否则参数还是会被绕过：

1. **关掉 Spotify 自带的开机自启**
   Spotify → 设置 → 关掉「开机时自动启动 Spotify」。
   （这个自启是 Spotify 自己拉起的，不带参数。）

2. **用启动器图标替换 Dock / 登录项里的 Spotify**
   - 把 `/Applications/Spotify (代理).app` 拖进 Dock，把原来的 Spotify 图标移出 Dock。
   - 系统设置 → 通用 → 登录项，添加 `Spotify (代理).app`（若需要开机自启）。

   想让它在 Dock 里更好认，可以自己换个图标：选中 App → ⌘I → 把图标图片拖到左上角。

## 验证是否生效

```bash
# ① 启动参数带上了
ps -o command= -p $(pgrep -x Spotify)
# 应看到 .../Spotify --proxy-server=http://127.0.0.1:59062

# ② TUN 和系统代理都是关的
scutil --proxy | grep -E "HTTPEnable|HTTPSEnable"        # 都应为 0
curl -s --unix-socket /tmp/verge/verge-mihomo.sock http://localhost/configs \
  | python3 -c "import sys,json;print('tun:',json.load(sys.stdin)['tun']['enable'])"   # False

# ③ Spotify 流量进了 mihomo，且走的是代理节点
curl -s --unix-socket /tmp/verge/verge-mihomo.sock http://localhost/connections \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
sp=[c for c in (d.get('connections') or []) if 'spotify' in ((c.get('metadata',{}).get('host') or '').lower())]
print('spotify 连接数:', len(sp))
for c in sp: print('  ', c['metadata'].get('host'), '->', c.get('chains'))
"

# ④ 端到端：在 Spotify 里放一首歌，确认能播放、能搜索、能浏览
```

## 测试

```bash
./tests/test_launcher.sh
```

覆盖端口读取（正常/带引号/缺键/非数字/文件不存在）、代理参数提取、五态判断、etime 换算。不依赖本机是否在跑 Clash，也不会启动或退出 Spotify。

## 已知限制

- **Clash 必须运行**：代理端口是死的时 Spotify 完全连不上。TUN 方案同理。
- **Spotify 界面和更新模块仍会直连 CloudFront**（`*.cloudfront.net`）。这是无害的，那条链路没被墙。
- **Spotify 自动更新不影响本方案**：参数是每次启动时传的，不改 App 包，所以不会被更新覆盖。
- 如果手动从 Finder/Spotlight 打开 `/Applications/Spotify.app`（而不是启动器），代理会失效。这正是要把 Dock 图标换成启动器的原因。

## 排错

双击 App 时，`launcher.sh` 的 stderr 会被 App 外壳重定向到日志里（正常情况下是空的）：

```bash
cat ~/Library/Logs/SpotifyLauncher.log
```

直接跑 `./launcher.sh` 时不会写这个文件，输出就在终端里。

### 抓「歌全变灰」的现场（临时诊断）

睡眠唤醒后歌全变灰的**根因还没找到**。已确认的是：这台机器在电池上每十几分钟 DarkWake 一次（每次只持续 2–19 秒），唤醒瞬间到代理节点的路由不通，Spotify 走代理的连接会成批失败 —— 但实测它自己会在几秒内重连，所以「界面为什么一直灰着」还没有解释。

`tools/spotify-proxy-watch.sh` 用来抓下一次复现时的现场：

```bash
tools/spotify-proxy-watch.sh &                    # 启动
kill "$(cat /tmp/spotify-proxy-watch.pid)"        # 停止
```

日志在 `~/Library/Logs/spotify-proxy-watch.log`。只在 Spotify 运行时才探测（15 秒一次），只在**状态变化**（代理通→不通、Spotify 连着→断开）和**睡眠唤醒后**记录，另有约 5 分钟一次的心跳。看到 `proxy=ok(...)` 配 `sp_conn=0` 的那一行，就是复现现场。

这是个临时工具，根因找到后连同这段一起删掉。