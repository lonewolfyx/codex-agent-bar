# Codex 额度查询实现说明

本项目禁止直接请求 `https://chatgpt.com/backend-api/wham/usage` 获取额度数据。真实查询必须通过官方公开的 `codex app-server` 服务完成。

参考文档：

- https://developers.openai.com/codex/app-server

## 目标

第一版真实查询能力建议只做「只读」：

- 启动本机 `codex app-server`。
- 使用 app-server JSON-RPC 查询当前账号信息和 ChatGPT/Codex rate limits。
- 在菜单栏展示 5 小时窗口和 1 周窗口的「剩余额度百分比」。
- 在 popover 里展示窗口名称、剩余额度、已用额度、重置时间、最后刷新时间。
- 不直接读取或保存 ChatGPT access token。
- 不请求任何未公开的 ChatGPT backend URL。

## 禁止方案

不要使用下面的接口：

```text
GET https://chatgpt.com/backend-api/wham/usage
```

原因：

- 这是 ChatGPT 后端内部接口，不应该作为本工具的数据源。
- 需要直接处理 ChatGPT access token，安全边界更差。
- 官方 Codex app-server 已经提供账号和 rate limit 查询能力。

## 推荐方案

使用本机 Codex CLI 启动 app-server：

```bash
codex app-server
```

官方文档说明 app-server 默认支持 `stdio` transport，消息格式是 newline-delimited JSON，也就是每条 JSON-RPC 消息一行。

也可以使用其他 transport：

```bash
codex app-server --listen ws://127.0.0.1:4500
codex app-server --listen unix://
```

第一版 macOS menubar 工具建议使用默认 `stdio`：

- Swift 用 `Process` 启动 `codex app-server`。
- `standardInput` 写入 JSONL 请求。
- `standardOutput` 按行读取 JSONL 响应和通知。
- App 退出时终止子进程。

## 初始化流程

app-server 连接建立后，必须先发送 `initialize` 请求，然后发送 `initialized` 通知。官方文档说明，初始化前发送其他请求会被拒绝。

请求：

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "codex_agent_bar",
      "title": "Codex Agent Bar",
      "version": "0.1.0"
    }
  }
}
```

通知：

```json
{
  "method": "initialized",
  "params": {}
}
```

注意：app-server 的 wire format 可以省略 `"jsonrpc": "2.0"` 字段。为了贴近官方示例，文档中的请求也省略它。

## 查询账号状态

先用 `account/read` 判断当前账号和认证状态：

```json
{
  "method": "account/read",
  "id": 1,
  "params": {
    "refreshToken": false
  }
}
```

ChatGPT 账号响应示例：

```json
{
  "id": 1,
  "result": {
    "account": {
      "type": "chatgpt",
      "email": "user@example.com",
      "planType": "pro"
    },
    "requiresOpenaiAuth": true
  }
}
```

处理建议：

- `account == null`：显示未登录。
- `account.type == "chatgpt"`：可以查询 ChatGPT/Codex rate limits。
- `requiresOpenaiAuth == true` 且没有 ChatGPT 账号：提示用户先用 Codex 登录。
- API key-only 或 Bedrock 模式不一定能提供 ChatGPT/Codex 订阅额度。

## 查询额度

使用 `account/rateLimits/read`：

```json
{
  "method": "account/rateLimits/read",
  "id": 2
}
```

响应示例：

```json
{
  "id": 2,
  "result": {
    "rateLimits": {
      "limitId": "codex",
      "limitName": null,
      "primary": {
        "usedPercent": 25,
        "windowDurationMins": 300,
        "resetsAt": 1730947200
      },
      "secondary": {
        "usedPercent": 42,
        "windowDurationMins": 10080,
        "resetsAt": 1730950800
      },
      "rateLimitReachedType": null
    },
    "rateLimitsByLimitId": {
      "codex": {
        "limitId": "codex",
        "primary": {
          "usedPercent": 25,
          "windowDurationMins": 300,
          "resetsAt": 1730947200
        },
        "secondary": null
      }
    },
    "rateLimitResetCredits": {
      "availableCount": 2
    }
  }
}
```

字段解释：

- `rateLimits`：向后兼容的单 bucket 视图。
- `rateLimitsByLimitId`：多 bucket 视图，key 是 metered `limit_id`，例如 `codex`。
- `limitId`：计量 bucket 标识。
- `limitName`：可选的人类可读名称。
- `usedPercent`：当前窗口内已使用百分比。
- `windowDurationMins`：额度窗口长度，单位分钟。
- `resetsAt`：下一次重置的 Unix 秒级时间戳。
- `planType`：服务端返回时表示这个 bucket 对应的 ChatGPT 计划类型。
- `credits`：服务端返回时表示工作区剩余 credit 细节。
- `rateLimitReachedType`：服务端分类出的限额触达状态。
- `rateLimitResetCredits`：可用的 earned reset 次数。

## 剩余额度换算

app-server 返回的是 `usedPercent`，但本工具菜单栏显示的是「剩余可使用额度」。

换算：

```swift
let remainingPercent = max(0, min(100, 100 - usedPercent))
```

颜色规则：

```text
0% - 20%     红色
21% - 50%    黄色
51% - 100%   绿色
```

如果 `usedPercent = 58`，菜单栏显示 `42%`，颜色为黄色。

如果 `usedPercent = 82`，菜单栏显示 `18%`，颜色为红色。

## 窗口映射

优先按 `windowDurationMins` 判断窗口名称：

```text
300     -> 5h
10080   -> 1w
```

如果服务端返回其他窗口长度，可以按分钟动态格式化：

- 小于 1440 分钟：显示为 `Nh`。
- 大于等于 1440 分钟：显示为 `Nd`。
- 无法识别时：显示 `limitName` 或 `limitId`。

## Swift 实现模块建议

建议把真实查询拆成 4 个模块：

- `CodexAppServerClient`
  负责启动 `codex app-server`、写入 JSONL、读取 JSONL、按 `id` 匹配响应、接收通知。

- `CodexAccountService`
  负责调用 `account/read`，识别账号类型、email、planType、登录状态。

- `CodexRateLimitService`
  负责调用 `account/rateLimits/read`，选择 `rateLimitsByLimitId["codex"]` 或 fallback 到 `rateLimits`。

- `QuotaStore`
  负责把 `usedPercent` 转成 `remainingPercent`，更新菜单栏 UI、popover UI、错误状态和最后刷新时间。

## 事件与自动更新

app-server 会发送通知。和额度相关的通知包括：

```text
account/updated
account/rateLimits/updated
```

建议策略：

- App 启动时查询一次 `account/read` 和 `account/rateLimits/read`。
- 收到 `account/rateLimits/updated` 时刷新 UI。
- 收到 `account/updated` 时重新读取账号和额度。
- 兜底每 30 秒主动查询一次 `account/rateLimits/read`。
- 用户点击刷新按钮时立即查询一次。

## 错误状态

第一版建议覆盖这些状态：

- 找不到 `codex` CLI：提示安装或配置 `PATH`。
- `codex app-server` 启动失败：显示启动错误。
- 初始化失败：显示 JSON-RPC 初始化错误。
- 未登录 ChatGPT：提示先执行 Codex 登录。
- 当前认证模式不支持 ChatGPT rate limits：显示认证模式不支持。
- 查询失败：显示 JSON-RPC error message。
- 响应格式变化：显示解析失败，并保留上一次成功数据。

## 安全边界

第一版不要做这些事：

- 不直接读取 `~/.codex/auth.json` 中的 access token。
- 不调用 `https://chatgpt.com/backend-api/wham/usage`。
- 不保存任何 ChatGPT token。
- 不把 token、完整 JSON 响应里的敏感字段写入日志。
- 不自动修改 Codex 的认证文件。

## 第一版落地顺序

1. 保留当前 mock UI。
2. 新增 `CodexAppServerClient`，只完成启动、初始化、发送请求、读取响应。
3. 新增 `account/read` 调用，确认账号状态。
4. 新增 `account/rateLimits/read` 调用，解析 `usedPercent`、`windowDurationMins`、`resetsAt`。
5. 把 `usedPercent` 转成菜单栏需要的 `remainingPercent`。
6. 接入 `QuotaStore`，替换 mock 数据。
7. 增加错误态 UI 和最后刷新时间。
