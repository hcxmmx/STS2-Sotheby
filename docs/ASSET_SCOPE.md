# 资源来源与授权范围

本仓库采用源码与第三方素材分离的方式。根目录 MIT License 适用于作者可授权的项目代码和文档；下表列出的第三方内容不通过该 MIT License 获得授权。

| 内容 | 来源及权利范围 | 本仓库是否包含文件本体 |
| --- | --- | --- |
| C# 桥接、GDScript、项目编写的着色器、场景组织与构建工具 | Hcxmmx，MIT | 是 |
| 苏芙比角色立绘、小人、骨骼、贴图、技能及公共选咒特效纹理与派生几何数据 | 《重返未来：1999》及对应权利方；派生转换不改变原素材权利归属 | 否 |
| 英文角色配音、原作台词、角色故事与资料文本 | 《重返未来：1999》及对应权利方 | 否 |
| 导出的原作布局、语音配置、Timeline、挂点和材质配置 | 原作配置或其转换结果，单独于自有代码处理 | 否 |
| 五张同路径覆盖图片 | 基于原作角色美术制作的适配图；对应原作美术权利仍保留 | 否 |
| 游戏 DLL、Harmony DLL、GodotSharp DLL、Spine runtime 与开发扩展 | 分别属于其权利方及各自许可范围 | 否 |
| 字体 | 见下文独立声明 | 否 |

`asset_manifest.json` 是本版本构建用的路径、大小与 SHA-256 列表，不包含素材内容。脚本从本地素材目录或本机已安装模组的 PCK 恢复文件；恢复后的文件仍属于本地第三方资源，不因此变为 MIT 许可的项目源码。

## 字体

根据本机实际使用文件的内嵌 name 表核对：

- `Cover/fonts/hwzs.ttf`：STZhongsong / 华文中宋，文件内标注 Changzhou SinoType Technology Co., Ltd. / 常州华文印刷新技术有限公司版权所有。本项目没有为该字体额外授予任何许可；源码仓库不分发该文件。独立分发完整资源包时，字体的分发权限需要另行核实或改用获准分发的替代字体。
- `Cover/fonts/subtitle_en.ttf`：Source Han Sans CN Regular / 思源黑体 CN Regular。本机此旧文件内嵌 Adobe Systems Incorporated 2014版权声明和 Apache License 2.0声明。其许可独立于项目 MIT 许可；本仓库也不携带该字体文件。这里记录的是实际文件声明，不以其他版本的字体许可替代。

## 同路径覆盖范围

其余自有资源统一使用 `res://Sotheby_Hcxmmx/`；下面五张图片保留游戏原路径：

```text
res://images/packed/character_select/char_select_silent.png
res://images/packed/character_select/char_select_silent_locked.png
res://images/ui/top_panel/character_icon_silent.png
res://images/ui/top_panel/character_icon_silent_outline.png
res://images/packed/map/icons/map_marker_silent.png
```

资源来源与项目依赖另见 [ATTRIBUTION.md](../ATTRIBUTION.md)。粉丝向、非商业说明描述本模组的发布用途，不应被理解为原权利方的授权证明。
