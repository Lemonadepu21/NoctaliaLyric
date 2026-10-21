# 设置参考


插件设置由所有组件共享；右键打开的外观设置对各组件独立生效。

### 播放器设置

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `player` | 空 | 优先显示正在播放的播放器；可指定实例名或播放器前缀 |
| `splayer_lyrics` | `true` | MPRIS 无歌词时启用 SPlayer 本机接口回退 |
| `splayer_port` | `25884` | SPlayer API 端口；仅连接 `127.0.0.1`，切歌读取并缓存 |
| `poll_interval` | `30000` | 仅播放时校准位置，单位 ms；范围 10000–120000 |

`poll_interval` 是低频校准间隔，不是画面刷新间隔。暂停、切歌、跳转和播放器退出通过 D-Bus 信号处理；旧配置中小于 10000 的值按 10000 处理。

### 常用外观设置

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `text_width` | `260` | 歌词区域最大宽度；先完整展示，超过上限的单行逐字移位 |
| `second_line` | `next` | `next` 下一句、`metadata` 歌手、`off` 单行 |
| `font_size` | `13` | 单行字号 |
| `dual_font_size` / `secondary_font_size` | `10` / `8` | 双行当前句与第二行字号 |
| `content_height` | `22` | 固定内容高度，封面和双行字号自动适配 |
| `line_gap` | `0` | 双行间距 |
| `show_progress` | `true` | 背景播放进度开关 |
| `transition` | `fade` | `none` 关闭、`fade` 淡入淡出 |

旧配置中的 `slide_up`、`slide_left` 会按淡入淡出处理。

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
| `padding_h` / `padding_v` | `4` / `1` | 内容水平与垂直内边距；进度填充覆盖水平内边距 |
| `time_offset` | `0` | 歌词时间偏移，单位 ms；正数提前，负数延后 |
| `hide_idle` / `hide_paused` | `true` / `false` | 无播放器／暂停时隐藏 |
| `dim_paused` | `true` | 暂停时使用柔和文字色 |
| `text_opacity` | `1.0` | 文字和封面不透明度 |
| `progress_color` / `progress_opacity` | `primary` / `0.25` | 进度填充颜色与不透明度 |
| `transition_duration` | `240` | 切句动效时长，范围 80–600 ms |

</details>

