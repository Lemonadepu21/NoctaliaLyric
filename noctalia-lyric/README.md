# Noctalia Lyric

在 Noctalia 状态栏显示专辑封面、同步歌词与播放进度。

| 插件 | 信息 |
| --- | --- |
| 插件 ID | `pupu/noctalia-lyric` |
| 状态栏组件 | `pupu/noctalia-lyric:bar` |
| 后台服务 | `pupu/noctalia-lyric:lyrics`，启用插件后自动运行 |

## 使用

启用插件后，在 **设置 → 状态栏 → 添加组件** 中添加 **Noctalia Lyric / bar**。左键打开原生媒体卡片，中键播放或暂停，右键调整组件外观。

支持单行与双行显示、按内容伸缩的宽度、超长单行逐字移位、淡入淡出和可开关的背景进度。字号、行距、边距、封面与颜色均可调整。

## 环境要求

Noctalia v5，插件 API 31 或更高；外部依赖为 `busctl`、`pango-view`。`busctl` 负责 MPRIS 通信，`pango-view` 负责文字排版。

优先使用 MPRIS `xesam:asText` 中带 LRC 时间戳的歌词。SPlayer 无 MPRIS 歌词时，默认从其本机 API 读取，端口为 `25884`，可在插件设置中调整或关闭。仅连接 `127.0.0.1`，按切歌读取并缓存，加载中最多尝试四次。

没有同步歌词时显示歌名与歌手。不查询在线歌词服务；远程封面按播放器提供的地址下载。逐字高亮暂不支持。

完整安装、配置与更新说明见 [项目主页](https://github.com/Lemonadepu21/NoctaliaLyric#readme)。
