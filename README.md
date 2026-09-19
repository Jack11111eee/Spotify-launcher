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

**但它治不了「歌变灰」。** 实测过灰屏现场：Spotify 一直连着代理（`sp_conn` 7~15，从未断开）、代理探测也通、mihomo 日志里没有任何错误 —— 界面却灰了，而且重启 Spotify 也修不好。那个故障不在这一层：它是客户端本地那份元数据缓存坏了，修法见下面的诊断记录。

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

**结论（2026-09-19 更新，仍未定论）：**

当天最后**恢复正常播放**了，但**没能归因到某一个动作** —— 期间客户端状态被反复改动过（清 `primary.ldb`、整份移走 `PersistentCache` 导致重新登录、多次重启），无法判断是哪一步起的作用。所以下面这条**不要当成可复现的修法**。

当天确认下来的事实：

- 坏的时候，灰掉的曲目**确实不能播**，客户端对它们**连播放请求都不发**。
- 清掉 `primary.ldb` **只改变渲染**（`▶ MV ·` 前缀消失），**不恢复播放**。「可用性判定存在这个文件里」已被证伪。
- **渲染和可播性是解耦的**：当天最后，歌单里那几行**仍然显示 `▶ MV ·`，但同一首 `楓` 正常播放**（位置持续推进）。所以「看起来灰」不等于「不能播」，别再用界面外观判断故障是否修复 —— 用能不能播来判断。
- 服务端侧看着是好的：歌单正文只含 114 个曲目 URI（不含可用性字段）；对真实曲目（`太陽之子` / `那天下雨了` / `擱淺` / `楓` / `暗號`）取 `metadata/4/track`，在 `NG / US / TW / JP / GB / from_token` **六个市场全部 200**，都带 audio 句柄，且结构上无可用性差异。
- **网页版能播、桌面版不能播**（同一账号、同一网络）—— 这是把问题锁定在客户端侧的关键对照。

没验成的一条线索：客户端在 `extended-metadata` 请求体里上报的 `country` 是 **NG**。把它改写成 `TW` 后，某一轮里 `楓` 从「stopped」变成「playing」；但**关掉改写后 `楓` 也能播**，所以**改写并非必要条件**，这条线索不成立（至少不是充分必要）。

**根因仍未定位。**

**注意：整份移走 `PersistentCache` 会把客户端登出** —— 登录态确实存在那里面（`prefs` 里的 `autologin.*` 不足以恢复）。要试必须先备份，且做好重新登录的准备。

以下保留 2026-09-18 / 09-19 的原始记录，其中**「修法」一节已作废**，只留作过程参考。

2026-09-18 首次诊断，2026-09-19 复现并定位到文件、验证了修法。

#### 现象

- 歌单里大量曲目发灰、点不动，点了弹「无法获取此内容」
- 起初只是按专辑（《太陽之子》），后来扩散到几乎全部
- 同一账号、同一代理、同一出口 IP，**网页版 `open.spotify.com` 能正常播放**
- 2026-09-19 复现时的确切样子：artist 行前面多一个 **`▶ MV ·`** 前缀（正常行只有 `周杰倫`），标题同时发灰。见下面的「怎么判断灰没灰」

#### 根因

客户端的曲目元数据（含可用性）**按版本缓存在本地**，存在这个 LevelDB 仓里：

```
~/Library/Application Support/Spotify/PersistentCache/Users/<user-id>/primary.ldb
```

拉取时客户端把「我手上这份是哪个版本」告诉服务端（见下面的「两层缓存」）。服务端认为版本没变就回 `304`，客户端继续用本地那份。

**一旦本地那份被写成「音频不可用」，它不会重新问一次。** 重启客户端也没用 —— 缓存是持久化的，重启只是把它读回来。

客户端对「音频不可用」的处理是**退回该曲目的音乐视频版本**，这就是 `▶ MV ·` 前缀和灰标题的来历。所以「灰」不是渲染故障，是客户端手里那份数据就是错的。

**缓存最初为什么会被写成「不可用」，仍未拿到直接证据**（坏掉的那份在 2026-09-19 已完整存档，见文末）。最可能的两个方向（均为推测）：某次元数据请求失败（网络抖动 / 5xx / 超时）被当成了「不可用」；或账号状态在那段时间短暂异常，客户端据此缓存了不可用，之后账号恢复却不重取。

#### 两层缓存（更正早先的说法）

早先这里把机制写成「`/metadata/4/` 上的条件请求（`If-None-Match` / `If-Modified-Since`）」—— **与现在客户端的行为不符**。2026-09-19 三次完整抓包里，每次会话只有 **1 次** `/metadata/4/track` 请求，客户端根本不靠它。

实际是两层，都用「版本号 + 哈希」而不是 HTTP 条件请求头：

```
# ① 歌单正文：revision diff
GET /playlist/v2/playlist/<id>/diff?revision=0,f447085452ce26c4ba2522ef7d0758b821a8c1bd
→ 304 Not Modified                      # 客户端继续用本地那份歌单

# ② 曲目元数据：请求体里逐条上报本地版本
POST /extended-metadata/v0/extended-metadata
  1: country=NG  catalog=premium
  2: uri=spotify:track:...   { 1: <版本号>, 2: <8 字节哈希> }
→ 逐条返回 304（用本地那份）或 200（带完整 Track protobuf）
```

这也解释了早先那个反常现象：桌面版对灰掉的歌**连请求都不发** —— 它认为自己本地已经有答案了。

> 想靠改写请求来逼它刷新是走不通的：把 `revision=` 摘掉、或把上报的版本删掉，服务端都直接回 **`400`**（实测 21/21 和 22 次请求全部 400）。这两个参数是必填的。**正解是清本地那份，不是改请求。**

#### 怎么定位到的

1. **先整份备份坏状态**（早先那次没来得及，坏状态被就地覆盖了）。这次在动手前把 `PersistentCache/` 整份存了下来。
2. 用 `spotify:playlist:<id>` 之类的方式把出问题的歌单调出来截图，确认 `▶ MV ·` 前缀。
3. 试出「彻底退出 Spotify → 移走 `primary.ldb` → 重启」，MV 前缀消失、标题恢复。
4. **反向验证因果**：把坏的那份 `primary.ldb` 放回去、重启 —— `▶ MV ·` **立刻整片复现**（同一张截图里，第 1~8 行是 `▶ MV · 周杰倫`，第 9~10 行是正常的 `周杰倫`）。再换回干净的那份，恢复正常。

第 4 步是关键：它把「坏状态就在这个文件里」从推测变成了对照实验。

#### 试过的办法

| 办法 | 结果 | 原因 |
|---|---|---|
| 重启客户端 | 无效 | 缓存持久化，重启只是读回来 |
| 清 `~/Library/Caches/com.spotify.client/`（700MB） | 无效 | 曲目元数据不在那儿 |
| 换出口节点（两个不同的美国节点） | 无效 | 与网络层无关 |
| 退出登录 → 重新登录 | **有害** | 与缓存是两回事，而且会把客户端卡在登录页（见文末） |
| 移走 `PersistentCache/`（**在 Spotify 运行时**） | 无效 | 进程开着 LevelDB，移动目录既不清内存状态也不清它已打开的文件，退出时还会把旧内容写回去。**必须先彻底退出再移** |
| **移走 `primary.ldb`（彻底退出后）** | **有效** | 正解，见上 |
| 摘掉 `/playlist/v2/.../diff` 的 `revision=` 参数 | 无效 | 服务端回 `400`，该参数必填 |
| 删掉 extended-metadata 请求体里上报的版本 | 无效 | 服务端回 `400`，该字段必填 |
| 把上报的版本号清零（保留字段） | 无效 | 服务端照回 `200` 完整元数据，界面仍灰 —— 说明刷新元数据**不等于**清掉可用性判定 |

#### 已排除的层面

| 层面 | 结论 | 证据 |
|---|---|---|
| 代理 / 节点 / 出口 IP | 正常 | 全程零绕行、零 4xx/5xx；换节点无任何变化 |
| 音频 CDN | 正常 | `206`，实测下载 3.1~4.6MB |
| DRM | 正常 | `widevine-license` 返回 `200` |
| 服务端授权 / 市场 | 排除 | `metadata/4/track` 在 `from_token/NG/US/TW/JP/HK` **六个市场全部 200**，带完整 `original_audio` 句柄和封面 |
| 发行时间门控 | 排除 | `earliest_live_timestamp` 早已过去 |
| Chromium HTTP 缓存 | 排除 | `~/Library/Caches/com.spotify.client/` 里没有任何相关条目，清掉也没用 |
| `ap-*.spotify.com` 不可达 | **无关** | 这批接入点在全球范围内都已下线（6 个国家的探测点，80/443 全部超时），但客户端根本不用它们 —— 它走 `guc3-spclient` / `dealer` |

顺带一条：启动器的第五态（没连着代理就重启）**在这个故障里永远不会触发** —— Spotify 从头到尾都连着代理，重启也修不好。

#### 怎么判断灰没灰（一条测量教训）

**别用标题的像素亮度判断。** 小字号抗锯齿会让最大像素值偏低，量出来「已点赞的歌曲」这种确定可播放的列表，标题峰值也是同样的 **113**（大标题是 255）—— 跟灰掉的那张歌单数值一模一样，区分不出来。这条弯路走过一次，白花了不少时间。

可靠的判据是**结构性的**：artist 行前面有没有 **`▶ MV ·`** 前缀。有就是退回了音乐视频版本（即「灰」），没有就是正常曲目行。分类信号比像素值可靠得多。

#### 两处被证伪的结论

诊断过程中走过两条弯路，都留在这里，免得以后重蹈：

1. **「根因是账号市场」——错。** 中途根据客户端 `customize` 响应里的 `country_code = "NG"`（尼日利亚区家庭组 Premium）判断「尼日利亚曲库小所以全灰」。但后续抓到 **46 次** `extended-metadata` 请求，`country` 全程都是 `NG`，**包括它正常播放音频的那几次**。country 与「歌变灰」同时存在，但互不相干。
2. **「移走 `PersistentCache` 有害」——错。** 早先这里写着它会让 `/api/token` 持续 `400`。实测那个 `400` 是 **DPoP 协议的正常握手**：服务端回 `{"error":"use_dpop_nonce"}` 并附上 nonce，客户端带上 nonce 重发随即 `200`。同一个请求连发两次、第一次 400 第二次 200，是设计如此，不是故障。

#### 下次再犯怎么办

**目前没有已知有效的办法。** 上面那版「清 `primary.ldb`」是错的（只改渲染，不改播放），已作废。

已排除的：清 `~/Library/Caches/com.spotify.client/`、清 `primary.ldb`、换节点、强制服务端返回完整元数据（把 extended-metadata 上报的版本号清零 → 服务端照回 200，界面照样灰）。

**下一步该试的**（都需要先备份，且注意 `PersistentCache` 含登录态）：

1. 在网页版 `open.spotify.com` 上打开同一张歌单 —— 能播就说明是客户端侧，不能播就是账号/市场侧。这一步最便宜，应该先做。
2. 若是客户端侧，再逐个试 `public.ldb`、`Users/<id>/cached`。

坏掉的那份已存档，放回去可以复现渲染层面的 `▶ MV ·`（但复现不了/修不好播放，见上）：

```
~/Library/Logs/spotify-grey-backup-20260919-181329/
  primary.ldb.BROKEN-confirmed     # 就是它，放回去就能复现
  PersistentCache/  prefs  Users/  # 2026-09-19 动手前的整份现场
```

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

**这个故障就藏在一个细节里**：默认抓包看到的是一片 `304 Not Modified`，看上去「一切正常」。要在插件里把 304 和请求体里的版本号打出来，才看得见「客户端一直在拿 304、一直在用本地那份错数据」：

```python
# extended-metadata 的请求体里逐条带着客户端本地版本，是判断「它凭什么拿 304」的关键
def request(flow):
    if "extended-metadata" in flow.request.pretty_host:
        open("/tmp/extmd.req", "wb").write(flow.request.content or b"")

def response(flow):
    print(flow.request.pretty_host, flow.request.path,
          flow.response.status_code, flow.client_conn.peername)
```

> 别指望靠改请求来修：`revision=` 和上报的版本号都是必填，摘掉就 `400`（见上面的「两层缓存」）。抓包在这里的用途是**看清机制**，修法是清本地那份 `primary.ldb`。

另一个识别技巧：日志里带上客户端源端口，再用 `lsof -nP -iTCP` 把端口对回进程，就能分清哪条请求来自桌面版、哪条来自浏览器 —— 两者都会请求 `spclient` / `pathfinder`，光看主机名分不开。

### 连接监视脚本

```bash
tools/spotify-proxy-watch.sh &                    # 启动
kill "$(cat /tmp/spotify-proxy-watch.pid)"        # 停止
```

日志在 `~/Library/Logs/spotify-proxy-watch.log`。只在 Spotify 运行时探测（15 秒一次），只在状态变化和唤醒后记录，另有约 5 分钟一次心跳。它排查「连接断没断」有用，但抓不到上面这个故障。