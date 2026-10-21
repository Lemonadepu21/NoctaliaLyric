# Noctalia Lyric

用于 Noctalia v5 状态栏的 MPRIS 歌词插件。专辑封面位于左侧，歌词位于右侧，支持单行滚动、双行显示、切句动效和背景播放进度。

**歌词由播放器提供。** 播放器需要通过 MPRIS `xesam:asText` 提供带时间戳的歌词；没有同步歌词时，组件直接显示歌名和歌手，不查询其他歌词来源。

## 功能

- **显示**：封面、当前句与下一句，或歌名与歌手；支持横栏和竖栏。
- **布局**：固定文字基线，宽度随内容伸缩，可调最大宽度、字号、行距、边距、颜色与封面圆角。
- **动效**：淡入淡出、向上滑入、向左滑入；超长单行自动滚动。
- **进度**：可开关的背景播放进度，支持颜色和透明度设置。
- **交互**：左键打开原生媒体卡片，中键播放／暂停，右键打开设置。
- **更新**：共享 D-Bus 信号监听；暂停时不周期性启动查询进程。

界面设置提供中文和英文。外层胶囊、栏高和组件缩放由 Noctalia 管理。

## 运行要求

| 项目 | 要求 |
| --- | --- |
| Noctalia | 已在 **5.3.0** 验证；要求插件 API **31 或更高** |
| 播放器 | 支持 MPRIS；同步歌词还需要带时间戳的 `xesam:asText` |
| `busctl` | 由 systemd 提供，用于 D-Bus 监听和状态读取 |
| `pango-view` | 由 Pango 提供，用于文字排版 |

不适用于 Noctalia v4／Quickshell。无需 `playerctl`，也不需要歌词服务 API 密钥。

## 安装

本仓库为私有仓库。另一台电脑需要登录具有仓库访问权限的 GitHub 账号。

### 1. 准备依赖

Arch Linux 可安装：

```sh
sudo pacman -S --needed git github-cli pango
```

`busctl` 由系统的 systemd 软件包提供。其他发行版请安装对应软件包，并确认以下命令均能找到程序：

```sh
command -v busctl pango-view
noctalia --version
```

### 2. 克隆并启用

先完成 GitHub 登录：

```sh
gh auth login
gh auth setup-git
```

将仓库克隆到 Noctalia 的插件目录：

```sh
plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/noctalia-lyric"
mkdir -p "$(dirname "$plugin_dir")"
gh repo clone Lemonadepu21/NoctaliaLyric "$plugin_dir"
noctalia msg plugins enable pupu/noctalia-lyric
```

如果该目录已经存在，请使用下方的[更新步骤](#更新)，不要覆盖原目录。

### 3. 添加状态栏组件

打开 **Noctalia 设置 → 状态栏 → 添加组件**，选择 **Noctalia Lyric / bar**，再调整位置与外观。

默认在没有可用播放器时隐藏。初次测试可先启动播放器，再播放或暂停一首歌曲。

## 操作

| 操作 | 行为 |
| --- | --- |
| 左键 | 打开／关闭 Noctalia 原生媒体卡片 |
| 中键 | 播放／暂停 |
| 右键 | 打开组件设置 |
| 悬停 | 查看完整歌词、歌曲信息与歌词状态 |

原生媒体卡片和中键操作使用 **Noctalia 当前选中的播放器**。插件的 `player` 筛选仅影响组件显示，不改变原生媒体卡片的播放器选择。

## 配置

插件设置由所有组件共享；右键打开的外观设置对各组件独立生效。

### 播放器设置

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `player` | 空 | 优先显示正在播放的播放器；可指定实例名或播放器前缀 |
| `poll_interval` | `30000` | 仅播放时校准位置，单位 ms；范围 10000–120000 |

`poll_interval` 是低频校准间隔，不是画面刷新间隔。暂停、切歌、跳转和播放器退出通过 D-Bus 信号处理；旧配置中小于 10000 的值按 10000 处理。

### 常用外观设置

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `text_width` | `260` | 歌词区域最大宽度；先完整展示，超过上限的单行再滚动 |
| `second_line` | `next` | `next` 下一句、`metadata` 歌手、`off` 单行 |
| `font_size` | `13` | 单行字号 |
| `dual_font_size` / `secondary_font_size` | `10` / `8` | 双行当前句与第二行字号 |
| `content_height` | `22` | 固定内容高度，封面和双行字号自动适配 |
| `line_gap` | `0` | 双行间距 |
| `show_progress` | `true` | 背景播放进度开关 |
| `transition` | `fade` | `none`、`fade`、`slide_up`、`slide_left` |

尺寸使用逻辑像素。短句自动收缩，长句展开至最大宽度；双行按较长一行确定宽度，封面、间距和左右边距另外计入总宽度。内容高度应适合当前状态栏胶囊；切句动效仅移动歌词。

<details>
<summary>其他外观参数</summary>

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `show_cover` | `true` | 显示封面 |
| `cover_size` / `cover_radius` | `28` / `6` | 封面大小与圆角 |
| `cover_gap` | `9` | 封面与文字间距 |
| `font_family` | 空 | 跟随栏字体，或填写系统字体名 |
| `font_weight` | `medium` | `normal`、`medium`、`semibold`、`bold` |
| `text_align` | `start` | `start`、`center`、`end` |
| `text_color` / `secondary_color` | `on_surface` / `on_surface_variant` | 当前句与第二行颜色 |
| `show_background` | `false` | 显示组件内部背景 |
| `background_color` / `background_radius` | `surface_variant` / `12` | 内部背景颜色与圆角 |
| `padding_h` / `padding_v` | `4` / `1` | 水平与垂直内边距 |
| `time_offset` | `0` | 歌词时间偏移，单位 ms；正数提前，负数延后 |
| `hide_idle` / `hide_paused` | `true` / `false` | 无播放器／暂停时隐藏 |
| `dim_paused` | `true` | 暂停时使用柔和文字色 |
| `text_opacity` | `1.0` | 文字和封面不透明度 |
| `progress_color` / `progress_opacity` | `primary` / `0.25` | 进度填充颜色与不透明度 |
| `transition_duration` | `240` | 切句动效时长，范围 80–600 ms |

</details>

## 在另一台电脑上测试

1. 确认插件已启用、组件已添加，播放器出现在 Noctalia 原生媒体卡片中。
2. 检查封面、歌名与歌手，以及左键、中键和右键操作。
3. 播放、暂停、拖动进度、切换歌曲，再退出播放器，检查进度与显示状态。
4. 如果播放器提供同步歌词，检查当前句、下一句、时间偏移和切句动效。
5. 分别测试单行和双行；使用较长的歌词检查自动滚动。

**只有歌曲信息、没有歌词，不一定是插件故障。** 支持 MPRIS 不等于提供歌词。可先查看播放器的总线名：

```sh
busctl --user list
```

找到 `org.mpris.MediaPlayer2.` 开头的名称，再读取其元数据。下面以 VLC 为例，请替换成实际总线名：

```sh
busctl --user get-property \
  org.mpris.MediaPlayer2.vlc \
  /org/mpris/MediaPlayer2 \
  org.mpris.MediaPlayer2.Player Metadata
```

没有 `xesam:asText`，或该字段不含 LRC 时间戳时，插件会回退显示歌曲信息。本机测试的 SPlayer 3.1.1 未通过该字段提供歌词，不能据此期待其他电脑上的 SPlayer 一定显示同步歌词。

需要重新读取状态时：

```sh
noctalia msg plugin pupu/noctalia-lyric:lyrics all refresh
```

反馈问题时，请附上 Noctalia 版本、播放器名称和版本、问题复现步骤，以及是否存在带时间戳的 `xesam:asText`。

## 更新

```sh
plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/noctalia-lyric"
git -C "$plugin_dir" pull --ff-only
noctalia msg plugins disable pupu/noctalia-lyric
noctalia msg plugins enable pupu/noctalia-lyric
```

若修改过本地代码，先处理本地修改，再更新。停用并重新启用可以同时重新加载代码与插件设置定义。

## 数据来源与限制

- 歌词仅来自播放器的 MPRIS 元数据，不扫描本地 LRC、不访问播放器 HTTP 接口，也不查询在线歌词。
- 仅支持逐句同步；逐字时间标签不会生成逐字高亮。详情见[逐字歌词能力边界](docs/word-lyrics.md)。
- 封面来自 `mpris:artUrl`。本地文件直接读取；远程封面会按播放器提供的地址下载，独立于歌词处理。
- 静态画面会复用缓存；滚动和滑入仍有 SVG 帧更新成本。实测范围与数据见[性能验证](docs/performance.md)，不代表所有设备或动画场景的占用。
- 1.1.x 的本地目录、SPlayer HTTP 和在线歌词选项已移除。升级后可删除旧配置中的 `lyrics_directory`、`splayer_lyrics`、`splayer_port`、`online_lyrics`。

## 开发检查

在仓库根目录执行：

```sh
lua tests/run.lua
noctalia plugins lint .
```

测试使用 Lua 运行与 Luau 兼容的代码，覆盖 MPRIS 事件、缓存、读取竞态、资源清理和布局行为；仍需在目标设备上验证实际显示与交互。

## 许可证

[MIT](LICENSE)
