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

**结论：跟这个启动器无关，是账号所属市场的问题。**

2026-09-18 做过一次完整诊断（用 mitmproxy 拿到了 HTTP 层可见性）。

**根因：账号的国家/地区是尼日利亚（NG）。** 从客户端的 `user-customization-service/v1/customize` 响应里直接读得到：

```
country_code      = "NG"
financial-product = "pr:premium,tc:0,rt:v2_NG_default_new-family-sub-1m_0_NGN_default"
name              = "Spotify Premium"
multiuserplan-member-type = "FAMILY_MEMBER"
```

Spotify 的曲库授权**按国家给**。客户端只把账号所属市场有授权的曲目画成可播放；尼日利亚区曲库极小，周杰伦和绝大多数华语歌都不在其中 —— 于是整片变灰。

**为什么以前能用**（推断，没有直接证据）：Spotify 允许 Premium 用户在境外使用约 14 天，期间按 IP 所在市场供曲。长期挂在境外节点上，窗口到期后市场被打回注册地 NG。这能解释「先灰一部分、后来全灰」的恶化过程。

**已排除的层面：**

| 层面 | 结论 | 证据 |
|---|---|---|
| 代理 / 节点 / 出口 IP | 正常 | 全程零绕行、零 4xx/5xx；换节点（美国 DMIT → 美国住宅）无任何变化 |
| 音频 CDN | 正常 | `206`，实测下载 3.8~5.7MB |
| DRM | 正常 | `widevine-license` 返回 `200` |
| 曲目元数据 / 服务端授权 | 排除 | `metadata/4/track` 在 `from_token/NG/US/TW/JP/HK` **六个市场全部 200**，带完整 `original_audio` 句柄和封面 |
| 发行时间门控 | 排除 | `earliest_live_timestamp` 早已过去 |
| HTTP 缓存投毒 | 排除 | Chromium 缓存里没有任何相关条目 |
| `ap-*.spotify.com` 不可达 | **无关** | 这批接入点在全球范围内都已下线（6 个国家的探测点，80/443 全部超时），但客户端根本不用它们 —— 它走 `guc3-spclient` / `dealer` |

桌面版对灰掉的歌**连请求都不发** —— 点击时抓包日志零新增，弹的「无法获取此内容」是纯客户端行为：它本地就已经判定这些曲目在当前市场不可用，所以没有可发的请求。所以第五态（没连着代理就重启）**永远不会触发** —— Spotify 从头到尾都连着代理。

**试过但没有用的修复：**

- 清 `~/Library/Caches/com.spotify.client/`（700MB）→ **无效**。跟缓存无关。
- 换出口节点 → **无效**。问题不在网络层。
- 移走 `~/Library/Application Support/Spotify/PersistentCache/` → **无效**。**并且更正一处早先写错的结论**：当时判断它「有害」，理由是移走后 `/api/token` 一直返回 `400`。实测那 400 是 **DPoP 协议的正常握手**（响应体是 `{"error":"use_dpop_nonce"}`），客户端带 nonce 重发随即 `200`。那不是故障。
- **退出登录 → 重新登录**（早先这里推荐过）→ **不要做。** 它会把客户端卡在登录页，报 `accesspoint:34`。登录页上「防火墙可能正在拦截 Spotify」那句提示是误导 —— 网络完全正常，那是客户端本地状态的问题（那次是浏览器 OAuth 其实已经走通、令牌也拿到了，界面没跟上，重启一次即恢复）。

**真正的修复**：把账号的国家/地区改成实际所在地区（[spotify.com/account](https://www.spotify.com/account) → 编辑个人资料）。Spotify 限制**每 14 天只能改一次**；Premium 改区通常需要**新地区的付款方式**。

**怎么抓这一层。** mihomo 只记 TCP 连接，`tools/spotify-proxy-watch.sh` 只看得见连接断没断，**两者都看不到 HTTP 状态码**（CDN 返回 403 和 200 在它们眼里一样）。要看 HTTP 层，把 mitmproxy 串在 Clash 前面：

```bash
mitmdump --mode upstream:http://127.0.0.1:59062 -p 8888
open -a Spotify --args "--proxy-server=http://127.0.0.1:8888" "--ignore-certificate-errors"
```

`--ignore-certificate-errors` 是这里的关键：Spotify 是 CEF 内核，这个 Chromium 开关让它直接接受 mitmproxy 的自签证书，**不需要往系统钥匙串装 CA**，全程不改 macOS 系统设置。测完退出 Spotify，用 `./launcher.sh` 重新拉起即可回到正常方式。

```bash
tools/spotify-proxy-watch.sh &                    # 启动
kill "$(cat /tmp/spotify-proxy-watch.pid)"        # 停止
```

日志在 `~/Library/Logs/spotify-proxy-watch.log`。只在 Spotify 运行时探测（15 秒一次），只在状态变化和唤醒后记录，另有约 5 分钟一次心跳。它排查「连接断没断」有用，但抓不到上面这个故障。