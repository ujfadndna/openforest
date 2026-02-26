# OpenForest

一个开源的专注计时器，灵感来自 Forest。在专注时种下一棵树，分心则树会枯萎。

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

## 功能

- **三种计时模式**：正计时 / 倒计时 / 番茄钟
- **失焦检测**（桌面端）：离开窗口超时则树枯萎
- **树种系统**：橡树、松树、樱花、竹子、枫树，各有独特外形和动效
- **标签系统**：自定义颜色标签，按标签统计专注时长
- **金币商店**：完成专注获得金币，解锁新树种
- **统计页**：今日 / 本周 / 本月 / 按标签，图表展示
- **主题**：跟随系统 / 浅色 / 深色

## 截图

> 待补充

## 快速开始

**环境要求**

- Flutter 3.x（`flutter --version` 确认）
- Dart 3.0+

**运行**

```bash
git clone https://github.com/your-username/openforest.git
cd openforest
flutter pub get
flutter run -d windows   # 或 macos / linux
```

**构建**

```bash
flutter build windows    # Windows 可执行文件
flutter build macos      # macOS .app
flutter build linux      # Linux 可执行文件
```

## 项目结构

```
lib/
├── core/
│   ├── timer_service.dart      # 计时核心逻辑
│   ├── coin_service.dart       # 金币计算
│   └── focus_detector.dart     # 失焦检测（桌面端）
├── data/
│   ├── database.dart           # SQLite 初始化
│   ├── models/                 # 数据模型
│   └── repositories/           # 数据访问层
├── features/
│   ├── timer/                  # 计时器页面
│   ├── stats/                  # 统计页面
│   ├── shop/                   # 商店页面
│   └── settings/               # 设置页面
└── main.dart
assets/
└── trees/
    └── trees.json              # 树种配置
```

## 技术栈

| 依赖 | 用途 |
|------|------|
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | 状态管理 |
| [drift](https://pub.dev/packages/drift) | SQLite ORM |
| [fl_chart](https://pub.dev/packages/fl_chart) | 统计图表 |
| [window_manager](https://pub.dev/packages/window_manager) | 桌面窗口管理 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 设置持久化 |

## 添加树种

编辑 `assets/trees/trees.json`，新增一条记录：

```json
{
  "id": "willow",
  "name": "柳树",
  "price": 150,
  "unlocked": false,
  "description": "垂柳依依，随风摇曳"
}
```

然后在 `lib/features/timer/tree_painter.dart` 的 `_kStyles` 里添加对应的视觉参数。

## License

MIT
