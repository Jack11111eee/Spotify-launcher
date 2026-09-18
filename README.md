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

最后一条状态是防御性的：光看命令行参数看不出连接是不是真的还在，所以启动器会去查 Spotify 的网络子进程是不是还连着代理端口，没连着就重启一次。

**但它治不了「歌变灰」。** 实测过灰屏现场：Spotify 一直连着代理（`sp_conn` 7~15，从未断开）、代理探测也通、mihomo 日志里没有任何错误 —— 界面却灰了，而且重启 Spotify 也修不好。那个故障不在这一层，详见下面的诊断记录。

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

### 「歌变灰」的诊断记录

**结论：桌面客户端本地缓存了错误的「不可用」元数据，而且不会自我纠正。跟这个启动器、代理、网络、账号市场都无关。**

2026-09-18 做了一次完整诊断，最终定位到这一层。

#### 现象

- 桌面版里大量曲目变灰、点不动，点了弹「无法获取此内容」
- 起初只是按专辑（《太陽之子》），后来扩散到几乎全部
- 同一账号、同一代理、同一出口 IP，**网页版 `open.spotify.com` 能正常播放**
- 当天还伴随一次登录故障（与灰歌无关，见文末）

#### 根因

客户端把曲目的可用性**缓存在本地**，之后用条件请求（`If-None-Match` / `If-Modified-Since`）去校验。服务端返回 `304 Not Modified` 时，它就继续沿用本地那份数据。

**一旦缓存里被写进了「不可用」，它不会再重新问一次。** 重启客户端也没用 —— 缓存是持久化的，重启只是把它读回来。

这也解释了最反常的那个现象：桌面版对灰掉的歌**连请求都不发**（抓包里只有 CORS 预检 `OPTIONS`，没有正式 `GET`）。不是它不想请求，是它认为本地已经有答案了。

**缓存最初为什么会被写成「不可用」，没有拿到直接证据** —— 坏掉的那份状态在修复过程中被就地覆盖了。最可能的两个方向（均为推测）：某次元数据请求失败（网络抖动 / 5xx / 超时）被当成了「不可用」；或账号状态在那段时间短暂异常，客户端据此缓存了不可用，之后账号恢复却不重取。

#### 怎么定位到的

把 mitmproxy 串在 Clash 前面，并在插件里**摘掉 `/metadata/4/` 请求上的条件请求头**，逼服务端返回完整的 `200` 而不是 `304`。桌面版当场恢复：

```
22:48:56  desktop  GET   /metadata/4/track/...                    200
22:48:56  desktop  GET   /storage-resolve/v2/files/audio/...      200
22:48:56  desktop  POST  /playplay/v1/key/...                     200
22:48:57  desktop  206   audio4-fa.scdn.co/audio/...          3145728B
22:49:04  desktop  206   audio4-fa.scdn.co/audio/...          4550832B
```

随后把 mitmproxy 撤掉、用 `./launcher.sh` 恢复正常启动，**依然正常** —— 证明坏的就是那份缓存，刷新一次即可，不需要常驻中间层。

#### 试过的办法

| 办法 | 结果 | 原因 |
|---|---|---|
| 重启客户端 | 无效 | 缓存持久化，重启只是读回来 |
| 清 `~/Library/Caches/com.spotify.client/`（700MB） | 无效 | 曲目元数据不在那儿（清掉后灰歌依旧） |
| 换出口节点（美国 DMIT → 美国住宅） | 无效 | 与网络层无关 |
| 退出登录 → 重新登录 | **有害** | 与缓存是两回事，而且会把客户端卡在登录页（见文末） |
| 移走 `Application Support/Spotify/PersistentCache/` | 无效 | 灰歌依旧。**但早先「它有害」的判断是错的**，见下面的「两处被证伪的结论」 |

#### 已排除的层面

| 层面 | 结论 | 证据 |
|---|---|---|
| 代理 / 节点 / 出口 IP | 正常 | 全程零绕行、零 4xx/5xx；换节点无任何变化 |
| 音频 CDN | 正常 | `206`，实测下载 3.1~4.6MB |
| DRM | 正常 | `widevine-license` 返回 `200` |
| 服务端授权 / 市场 | 排除 | `metadata/4/track` 在 `from_token/NG/US/TW/JP/HK` **六个市场全部 200**，带完整 `original_audio` 句柄和封面 |
| 发行时间门控 | 排除 | `earliest_live_timestamp` 早已过去 |
| Chromium HTTP 缓存 | 排除 | `~/Library/Caches/com.spotify.client/` 里没有任何相关条目，清掉也没用。坏的是**另一份**缓存（见上面的「根因」） |
| `ap-*.spotify.com` 不可达 | **无关** | 这批接入点在全球范围内都已下线（6 个国家的探测点，80/443 全部超时），但客户端根本不用它们 —— 它走 `guc3-spclient` / `dealer` |

顺带一条：启动器的第五态（没连着代理就重启）**在这个故障里永远不会触发** —— Spotify 从头到尾都连着代理，重启也修不好。

#### 两处被证伪的结论

诊断过程中走过两条弯路，都留在这里，免得以后重蹈：

1. **「根因是账号市场」——错。** 中途根据客户端 `customize` 响应里的 `country_code = "NG"`（尼日利亚区家庭组 Premium）判断「尼日利亚曲库小所以全灰」。但后续抓到 **46 次** `extended-metadata` 请求，`country` 全程都是 `NG`，**包括它正常播放音频的那几次**。country 与「歌变灰」同时存在，但互不相干。
2. **「移走 `PersistentCache` 有害」——错。** 早先这里写着它会让 `/api/token` 持续 `400`。实测那个 `400` 是 **DPoP 协议的正常握手**：服务端回 `{"error":"use_dpop_nonce"}` 并附上 nonce，客户端带上 nonce 重发随即 `200`。同一个请求连发两次、第一次 400 第二次 200，是设计如此，不是故障。

#### 下次再犯怎么办

**已知有效的办法**就是上面那条：把 mitmproxy 串上去，在插件里摘掉 `/metadata/4/` 的条件请求头，让它重新拉一次。刷一次之后就可以撤掉 mitmproxy，用 `./launcher.sh` 恢复正常启动 —— 实测刷新是持久的，不需要常驻中间层。

**还没找到不依赖 mitmproxy 的等效办法。** 试过的两条都不行：

- 清 `~/Library/Caches/com.spotify.client/`（700MB）→ 无效
- 移走 `Application Support/Spotify/PersistentCache/` → 无效

也就是说，那份坏掉的曲目可用性缓存**具体落在哪个文件里，目前还不清楚**。下次复现时**先把坏掉的状态整份备份下来再动手修**（这次没来得及，坏状态在修复过程中被就地覆盖了），两相对照就能定位到文件。

#### 附：同一天遇到的登录故障（与灰歌无关）

- **症状**：客户端卡在登录页，报 `accesspoint:34`，界面提示「防火墙可能正在拦截 Spotify」
- **排查**：网络完全正常 —— 登录需要的每条链路都通（`login5/v3/login` 200、`oauth2/device/authorize` 200、`/api/token` 200），那句防火墙提示是误导
- **真正原因**：客户端本地状态没跟上。浏览器 OAuth 其实已经走通、访问令牌也拿到了，但界面仍停在登录页
- **解决**：重启客户端即恢复
- **教训**：**不要点「退出登录」** —— 它会把客户端卡在登录页

### 怎么抓这一层

mihomo 只记 TCP 连接，`tools/spotify-proxy-watch.sh` 只看得见连接断没断，**两者都看不到 HTTP 状态码**（CDN 返回 403 和 200 在它们眼里一样）。要看 HTTP 层，把 mitmproxy 串在 Clash 前面：

```bash
mitmdump --mode upstream:http://127.0.0.1:59062 -p 8888
open -a Spotify --args "--proxy-server=http://127.0.0.1:8888" "--ignore-certificate-errors"
```

`--ignore-certificate-errors` 是这里的关键：Spotify 是 CEF 内核，这个 Chromium 开关让它直接接受 mitmproxy 的自签证书，**不需要往系统钥匙串装 CA**，全程不改 macOS 系统设置。测完退出 Spotify，用 `./launcher.sh` 重新拉起即可回到正常方式。

**这个故障就藏在一个细节里**：默认抓包看到的是一片 `304 Not Modified`，看上去「一切正常」。要看到真相，得在插件里把 `/metadata/4/` 请求上的条件请求头摘掉，逼服务端返回完整正文：

```python
def request(flow):
    if "/metadata/4/" in flow.request.path:
        for h in ("if-none-match", "if-modified-since"):
            flow.request.headers.pop(h, None)
```

摘掉之后客户端立刻恢复播放 —— **「摘掉就好」本身就是诊断结论**：它一直在拿 304、一直在用本地那份错数据。

另一个识别技巧：日志里带上客户端源端口，再用 `lsof -nP -iTCP` 把端口对回进程，就能分清哪条请求来自桌面版、哪条来自浏览器 —— 两者都会请求 `spclient` / `pathfinder`，光看主机名分不开。

### 连接监视脚本

```bash
tools/spotify-proxy-watch.sh &                    # 启动
kill "$(cat /tmp/spotify-proxy-watch.pid)"        # 停止
```

日志在 `~/Library/Logs/spotify-proxy-watch.log`。只在 Spotify 运行时探测（15 秒一次），只在状态变化和唤醒后记录，另有约 5 分钟一次心跳。它排查「连接断没断」有用，但抓不到上面这个故障。