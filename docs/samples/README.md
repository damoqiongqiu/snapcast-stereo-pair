# sample 调用栈样本与判读

本目录保存双机部署排障时 `sample <pid> 2` 抓取的调用栈现场（原报告 `samples/` 4 份文件的整理版）。
它们记录了旧 PortAudio 采集路径在 macOS 上无声卡死的现场。当前运行时已改用
CoreAudio IOProc 与持续 10 ms 时钟，以下内容保留用于历史分析和上游问题引用。

原始文件：`capture-sample.txt`、`sample2.txt`（ReadStream 睡眠环）、`sample5961.txt`、`s3.txt`（Pa_OpenStream 死等 coreaudiod）。
原始输出随 `/tmp` 清理丢失，以下为报告中记录的核心调用栈与判读结论，结构保持原样便于对照。

## 1. ReadStream 睡眠环（`capture-sample.txt` / `sample2.txt`）

```text
Sampling process <capture-blackhole-pa pid> for 1 second ...

Call graph:
    start_wqthread                      (in libsystem_pthread.dylib)
    _pthread_wqthread
    __pthread_start
     ...
    Pa_Sleep                            (in PortAudio)
    Pa_ReadStream                       (in PortAudio)
    main                                (in capture-blackhole-pa)
```

**判读**：线程停在 `Pa_Sleep` 且无任何错误码返回——BlackHole 设备停转后 PortAudio 阻塞读进入内部睡眠环，
永不返回、永不报错。看门狗补丁（`g_last_read_ms` + `Pa_AbortStream`）就是为这个场景设计的。
当前修复见 [BlackHole Capture Clock Design](../designs/2026-11-25-blackhole-capture-clock-design.md)。

## 2. Pa_OpenStream 死等 coreaudiod（`sample5961.txt` / `s3.txt`）

```text
Sampling process <capture-blackhole-pa pid> for 1 second ...

Call graph:
    mach_msg                            (in libsystem_kernel.dylib)
    mach_msg_trap
    __CFRunLoopServiceMachPort          (in CoreFoundation)
    __CFRunLoopRun
     ...
    Pa_OpenStream                       (in PortAudio)
    audio_hw_init
    main                                (in capture-blackhole-pa)
```

**判读**：栈顶 `mach_msg` 表示在等 mach 端口回复——coreaudiod 已卡死（深夜反复重启服务的副作用）。
此场景发生在打开流阶段，看门狗尚未接管，无法自愈；修复方式是 `sudo killall coreaudiod`。

## 3. 抓取与判读方法

```sh
# 抓采集进程 1 秒调用栈
sample $(pgrep -f capture-blackhole-pa) 1

# 抓 Snapclient 调用栈（排查连接/播放卡死）
sample $(pgrep -f 'snapclient tcp') 1
```

| 栈顶特征 | 结论 | 可否自愈 |
|---|---|---|
| `Pa_Sleep` ← `Pa_ReadStream` | 旧版 BlackHole 阻塞读睡眠环 | 历史路径；当前使用 CoreAudio IOProc |
| `mach_msg` ← `Pa_OpenStream` | coreaudiod 卡死 | ❌ `sudo killall coreaudiod` |
| `read` ← FIFO 写 | 读端关闭/管道满 | ✅ `write_channel` 重连（补丁） |

## 4. 报上游时如何引用

上游 issue 建议同时附上：
1. 本报告 `docs/field-debugging-report.md`（根因与修复分析）；
2. 本目录对应 sample 调用栈（证明卡死现场）；
3. `git diff` 形式的补丁（已合并于本仓库 `integration/`，可用 `git show <commit>` 提取）。
