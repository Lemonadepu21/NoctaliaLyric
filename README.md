# Noctalia Lyric

在 Noctalia 状态栏里查看当前歌词、专辑封面和播放进度。

歌词跟随播放器逐句切换；短句自动收缩，长句优先完整展开，超过设定宽度后按字符移位，逐步显示后半句。点击组件即可打开 Noctalia 原生媒体卡片，继续控制播放。

| 插件 | 信息 |
| --- | --- |
| 名称 | Noctalia Lyric |
| 插件 ID | `pupu/noctalia-lyric` |
| 状态栏组件 | `pupu/noctalia-lyric:bar` |
| 兼容性 | Noctalia v5，插件 API 31 及以上；已在 5.3.0 验证 |
| 界面语言 | 简体中文、English |

## 功能

- **封面与歌词**：左侧专辑封面，右侧当前歌词；可选择单行、当前句与下一句，或歌曲信息。
- **自适应宽度**：按文字长度调整组件宽度；可设置最大歌词宽度，超长单行逐字移位显示。
- **切句动效**：淡入淡出，也可关闭。
- **背景进度**：用胶囊背景中的填充显示播放进度，支持开关、颜色和透明度调整。
- **外观设置**：字号、行距、边距、封面尺寸、圆角和颜色均可调整；竖向状态栏使用紧凑封面显示。

## 安装

### 环境要求

- Noctalia v5，支持插件 API 31 或更高。
- 支持 MPRIS 的音乐播放器。**同步歌词需要播放器提供歌词数据**：支持 MPRIS 歌词及 SPlayer 本机接口，详见[歌词支持](#歌词支持)。
- `git`、`busctl`、`pango-view`。其中 `busctl` 通常由 systemd 提供，`pango-view` 由 Pango 提供。

Arch Linux 可安装依赖：

```sh
sudo pacman -S --needed git pango
```

### 添加插件源

1. 打开 **Noctalia 设置 → 插件 → 添加插件源**，选择 **Git 仓库**。
2. 名称填写 `NoctaliaLyric`，仓库地址填写：

   ```text
   https://github.com/Lemonadepu21/NoctaliaLyric.git
   ```

3. 在该来源中找到 **Noctalia Lyric**，启用插件。
4. 打开 **设置 → 状态栏 → 添加组件**，添加 **Noctalia Lyric / bar**。

播放一首歌曲后，组件会显示封面与歌词或歌曲信息。默认在没有播放器时隐藏。

也可以通过命令添加来源并启用，再到状态栏设置中添加组件：

```sh
noctalia msg plugins source add NoctaliaLyric git https://github.com/Lemonadepu21/NoctaliaLyric.git
noctalia msg plugins enable pupu/noctalia-lyric
```

安装方式遵循 [Noctalia 插件说明](https://docs.noctalia.dev/noctalia/plugins/)。

## 使用

| 操作 | 功能 |
| --- | --- |
| 左键点击 | 打开或关闭原生媒体卡片 |
| 中键点击 | 播放或暂停 |
| 右键点击 | 打开组件设置 |
| 悬停 | 查看完整歌词与歌曲信息 |

播放控制跟随 Noctalia 当前选中的播放器。插件设置中的播放器筛选只决定组件显示哪一个播放器。

### 调整显示

右键组件可调整外观。常用设置包括：

| 设置 | 作用 |
| --- | --- |
| 歌词最大宽度 | 短句收缩、长句展开的上限；不含封面与边距 |
| 第二行 | 显示下一句、歌手，或关闭以使用单行 |
| 单行／双行字号 | 分别控制单行、双行当前句与第二行的字号 |
| 内容高度与行距 | 调整双行的密度和上下留白 |
| 切句动效 | 开关淡入淡出与调整持续时间 |
| 背景进度 | 开关进度填充，调整颜色与透明度 |
| 歌词时间偏移 | 调整歌词同步；正值提前，负值延后，单位为毫秒 |

在 **设置 → 插件 → Noctalia Lyric** 中可选择播放器、开关 SPlayer 本机歌词回退及设置其 API 端口。完整参数见[设置参考](docs/settings.md)。

## 歌词支持

Noctalia Lyric 优先读取 MPRIS 歌词（`xesam:asText`），支持带 LRC 时间戳的逐句同步。

**SPlayer**：MPRIS 没有歌词时，默认从 SPlayer 本机 API 读取已加载的歌词。请保持其本地 API 服务可用，默认端口为 `25884`；修改过端口时，在插件设置中同步调整。插件仅连接 `127.0.0.1`，按切歌读取并缓存；歌词加载中最多尝试四次，不持续轮询。

**其他播放器能显示歌词，不代表它会通过 MPRIS 向其他应用提供歌词。** 若没有可用同步歌词，组件会显示歌名与歌手；这时仍可使用封面、播放进度和媒体控制。

歌词仅从播放器读取，不进行联网匹配，不扫描本地歌词文件。逐字高亮暂不支持。专辑封面使用播放器提供的地址；远程封面可能需要网络连接。

## 更新与移除

在 **设置 → 插件** 中更新 `NoctaliaLyric` 来源。已启用的插件会随来源更新重新加载。

命令行更新：

```sh
noctalia msg plugins update NoctaliaLyric
```

停用插件可停止运行；需要移除时，先删除状态栏组件，再移除插件源。

## 常见问题

**插件已启用，但状态栏里没有组件？** 还需要在状态栏设置中添加组件。若已经添加，请确认播放器已启动；默认无播放器时隐藏。

**有歌名却没有歌词？** 使用 SPlayer 时，请确认本机 API 可用、端口与插件设置一致；其他播放器需要通过 `xesam:asText` 提供带时间戳的歌词。仅提供歌名、歌手和进度时，组件会显示歌曲信息。

**双行文字被裁切？** 增大内容高度，或减小双行字号与行距；外层胶囊高度由 Noctalia 的状态栏设置控制。

## 反馈与开发

欢迎通过 [Issues](https://github.com/Lemonadepu21/NoctaliaLyric/issues) 反馈问题。请附上 Noctalia 与播放器版本、复现步骤；显示问题可附组件截图。

仓库根目录可运行以下检查：

```sh
lua tests/run.lua
noctalia plugins lint noctalia-lyric
```

实现与验证资料：[性能记录](docs/performance.md) · [逐字歌词支持范围](docs/word-lyrics.md)。

## 许可证

[MIT](LICENSE)
