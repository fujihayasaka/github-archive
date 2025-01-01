[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/hooks/v1/hooks_api.proto



## Services

<a name="github.spokes.hooks.v1.HooksAPI"></a>

### HooksAPI



<a name="github.spokes.hooks.v1.HooksAPI-RunPreReceiveHooks"></a>

#### RunPreReceiveHooks

RunPreReceiveHooks runs the pre-receive hooks on a file server host.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.hooks.v1.HooksAPI/RunPreReceiveHooks`

<a name="github.spokes.hooks.v1.RunPreReceiveHooksRequest"></a>

##### RunPreReceiveHooksRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  |  |
| sockstat | [github.spokes.types.v1.Sockstat](../../types/v1/sockstat.md#github.spokes.types.v1.Sockstat) |  | set of sockstat variables to pass to gitrpcd to setup the git hooks environment correctly. |
| reference_updates | [github.spokes.types.v1.ReferenceUpdate](../../types/v1/reference_update.md#github.spokes.types.v1.ReferenceUpdate) | repeated | the set of incoming reference updates for a push that are being evaluated in the hook. |
| hook_mode | [RunPreReceiveHooksRequest.HookMode](#github.spokes.hooks.v1.RunPreReceiveHooksRequest.HookMode) |  | The mode in which the pre-receive hooks can run |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.hooks.v1.RunPreReceiveHooksResponse"></a>

##### RunPreReceiveHooksResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| return_code | [int64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | the return code as being returned by the pre receive hook after its done running. a zero code represents success, while a non zero code represents failure. |
| output_message | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | the message returned by the hook (via its stdout) that can be passed on to the caller. The message can compose of multiple lines, each seperated by a newline. |
| error_message | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | the message returned by the hook (via its stderr) indicating the reason the hook failed, that can be passed on to the caller. The message can compose of multiple lines, each seperated by a newline. |



<a name="github.spokes.hooks.v1.RunPreReceiveHooksRequest.HookMode"></a>

### RunPreReceiveHooksRequest.HookMode


| Name | Number | Description |
| ---- | ------ | ----------- |
| HOOK_MODE_INVALID | 0 |  |
| HOOK_MODE_QUARANTINE | 1 | These hooks are run during the initial temprefs receive-pack process. During execution, these hooks rely on a GIT_QUARANTINE_DIR value that is computed and used by that initial receive-pack process and needs to be passed through as `GIT_SOCKSTAT_VAR_git_quarantine_dir. So we refer to these as the 'quarantine' hooks. NOTE: this mode cannot be called via Spokes API today by a consumer, but may be opened up in the future. |
| HOOK_MODE_BABELD | 2 | These hooks are run after landing the packfile and temprefs, and immediately before the commit-refs flow. These are also referred to as the regular hooks. NOTE: this mode cannot be called via Spokes API today, but may be opened up in the future. |
| HOOK_MODE_CUSTOM | 3 | Custom hooks that a customer can upload, these only run in GHES. Typically run as part of the babeld mode during a git push, but can be run independently as well (for e.g. when content is pushed via the API) |


