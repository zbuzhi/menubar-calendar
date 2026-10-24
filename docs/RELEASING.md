# 不知时日历 · 软件更新与发布

软件更新采用 Sparkle 2.10.0，依赖版本及下载校验由 SwiftPM 锁定。安装包发布到公开仓库 `zbuzhi/menubar-calendar` 的 Releases。兼容现有用户的更新渠道继续使用 `zbuzhi/calendar-holidays`：`updates/appcast.xml` 是签名软件更新清单；`index.json` 和 `years/` 仍只负责节假日数据，两者互不依赖。

项目对外名称及应用显示名称为「不知时日历」，源码仓库为 `menubar-calendar`。后续安装包命名为 `menubar-calendar-版本-universal.zip`，包内为 `不知时日历.app`；内部可执行文件仍为 `PerpetualCalendar`。图标由 `Resources/AppIcon.icon` 编译为 `Assets.car` 与兼容 `.icns`，发布时应使用完整构建目录。保留 bundle ID 与钥匙串账户，保证设置、小记和更新签名连续性。源码及安装包继续使用原仓库；签名清单保留现有地址，以兼容旧版更新器。以前的已签名包不修改、不重新命名，发布验证兼容其原有名称。

## 用户体验

- 设置 → 更新 → 软件更新：自动检查开关、当前版本、检查按钮、状态和版本记录。
- 默认每天检查一次；关闭开关后仍可手动检查。使用 Sparkle 自己的持久化设置与调度，不另存一份开关。
- 发现新版后由用户确认下载、安装与重启，不静默替换运行中的应用。不改变 bundle ID、设置或小记的存储位置。
- 节假日数据仍每 7 天检查，可单独手动更新；软件更新失败不影响日历或假期缓存。
- 更新清单与安装包均使用 Ed25519 签名，清单签名失败不放宽验证，安装包在解压前验证。关闭系统信息采集，不发送小记或日历设置。
- GitHub 网络不可用时不能下载软件更新，继续使用现有版本，稍后重试。

## 一次性初始化

```sh
./scripts/build-app.sh
python3 scripts/setup-updates.py
./scripts/build-app.sh
```

初始化使用 Sparkle 官方 `generate_keys`，私钥保存在登录钥匙串，service 为 `https://sparkle-project.org`，account 为 `com.perpetualcalendar.mac`。源码和安装包只包含公钥。初始化脚本不会静默替换已有公钥；已有配置与本机钥匙串不符时会停止。

务必通过安全途径备份签名钥匙串。不要将私钥、钥匙串导出、Apple 凭据或 GitHub Token 提交到仓库，也不要在日志输出私钥。丢失私钥且没有 Developer ID 签名的轮换途径时，现有用户可能必须手动下载安装新版本。

`updates/appcast.xml` 的初始清单没有安装包条目：它建立可用的签名检查渠道，不代表已有正式安装包可供下载。第一次正式发布后才写入对应安装包条目。现有 0.1.5 没有 Sparkle，需要手动安装一次含更新器的 0.1.6；此后才能在应用内更新。

## 准备版本

1. 更新 `Resources/Info.plist` 的 `CFBundleShortVersionString`（例如 0.2.0）和 `CFBundleVersion`（例如 11）；构建号必须递增。不要重复使用已发布版本号。
2. 在本机运行 `./scripts/check.sh`、`./scripts/build-app.sh`，核对 Intel 与 Apple Silicon 通用构建。
3. 写好本次更新说明，运行：

```sh
python3 scripts/prepare-release.py --notes Resources/ReleaseNotes-0.2.0.md
```

输出 `dist/releases/app-v版本/`：通用 zip、已签名 `appcast.xml`、说明及 `release.json`。脚本校验 bundle ID、更新地址、双架构、代码签名和钥匙串公钥，使用 `ditto` 保留框架符号链接，然后签名、复验安装包与清单。已存在的版本输出目录不会覆盖；修改包后须重新准备签名，不能手工修改已签名 XML。

## 免费托管与发布

默认在自己的 Mac 构建和签名，不新建 GitHub Actions 构建任务、不上传 Actions 产物或签名私钥。GitHub Releases 用于安装包托管，不需要自己的服务器。已有账号 Actions 的 $0 付费预算保持原样，节假日自动化仍只使用标准公开运行器。GitHub 服务规则以官方当前规定为准。

可使用 GitHub 官方 CLI（`gh`，需自行登录），先创建草稿供核对：

```sh
python3 scripts/publish-release.py dist/releases/app-v0.2.0
```

确认要对外发布该版本后：

```sh
python3 scripts/publish-release.py dist/releases/app-v0.2.0 --publish
```

发布脚本只允许既定公开仓库，复验本地文件与签名，拒绝构建号回退；上传后下载核对安装包 SHA-256，再公开 Release，最后用旧 blob SHA 条件更新清单，避免并发覆盖。网络中断可核对后重试，不替换已上传的不同包。若安装包已公开而清单更新失败，用户仍使用旧清单；修复后重新执行即可。

不使用 CLI 也可以：网页 Releases → 新建 `app-v版本`，上传生成的 zip，填写版本说明；先确认安装包可下载，再将**原始已签名** `appcast.xml` 上传到 `main/updates/appcast.xml`。不要使用 GitHub 自动生成的源码压缩包作为应用安装包，不要通过网页编辑已签名清单的空格或换行。

## Apple 签名与公证

Sparkle 签名和 GitHub 托管可以免费完成。Apple Developer ID 签名与公证属于另一套发行机制，需要对应 Apple 开发者资格，不会因接入自动更新自动获得。

当前本机无 Developer ID，默认构建仍为 ad-hoc 本地构建，**尚未经 Apple 公证**；免费更新签名不代表通过 Gatekeeper 的首次安装验证。正式面向普通用户分发，建议准备 Developer ID 并公证。

已有证书后可指定：

```sh
CALENDAR_SIGN_IDENTITY='Developer ID Application: 你的证书名称' ./scripts/build-app.sh
```

脚本从内到外签署 Sparkle helpers、框架和主应用，并开启 Hardened Runtime。随后使用自己的 Apple 公证凭据完成公证和 stapling，再执行 `prepare-release.py`。公证需要完整 Xcode 中的 `notarytool`/`stapler`；脚本不会代为购买资格或提交凭据。

## 验收

- `codesign --verify --deep --strict dist/不知时日历.app`。
- 安装目录与 app 名保持一致，最低 macOS 13，主程序与 Sparkle 均为双架构。
- 在隔离测试 .app 中检查：合法签名新版本可识别、初始无版本清单正常返回、篡改签名清单被拒绝；不要用真实用户设置域做自动化更新安装实验。
- 执行 `python3 Tests/check-software-updates.py dist/releases/app-v0.2.0` 可复验上述三种情况及 GitHub 真实更新地址；`python3 -m unittest discover -s Tests -p 'test_release_publisher.py' -v` 校验发布顺序、仅草稿、安装包变化、私有仓库、版本回退和并发保护，测试不访问 GitHub 或上传文件。
- 实际安装与重启应在正式发行包和目标系统上再验收，尤其是 Developer ID、公证、Intel 实机及登录自启。
