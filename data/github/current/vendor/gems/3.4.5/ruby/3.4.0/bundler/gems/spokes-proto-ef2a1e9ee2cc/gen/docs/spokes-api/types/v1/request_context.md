[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/request_context.proto



## Types

<a name="github.spokes.types.v1.RequestContext"></a>

### RequestContext
RequestContext is extra information that is used by Gitmon when figuring out
which quotas to apply and how to enforce them.

For more information see docs/gitmon.md


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| quality_of_service | [RequestContext.QualityOfService](#github.spokes.types.v1.RequestContext.QualityOfService) |  | <p>quality_of_service is the requested QoS for this request.</p> |
| user_id | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>user_id is the ID of the current actor. Some quotas are based on this.</p><p>If the actor is not known, use the default value (0).</p> |
| real_ip | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>real_ip is the IP address of the current actor. Some quotas are based on this.</p><p>If the actor's IP address is not known, use the default value (""). Do not provide IPs from our internal network.</p> |
| read_uncommitted | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>read_uncommitted should be set when the request is trying to read Git data during a 'git push' before _commit_refs has finished. When read_uncommitted is set, spokesd will try the current request on all replicas until it receives a success (<300). If all replicas respond with an error, the last error will be returned.</p> |
| transaction_state | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>transaction_state is a serialized data structure describing the state of a Spokes API write transaction. It includes information like the quarantine ID that identifies the path to the quarantine directory where new objects are placed on a replica, the list of replicas that successfully performed the object write(s), sockstat variables for the operation, and may include more fields moving forward. When making a Spokes Access API call during a transaction such as a `git push`, this field must be set to the value received in transaction API or write endpoint responses, scoped to the repository to which it applies.</p><p>This field is also known as the "push_state" in the GitauthAPI.</p> |
| read_after_write | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>read_after_write should be set when the request is trying to read data and the client expects to be able to read data that was written immediately before the read call. This is analogous to "use the primary mysql instance", though the implementation might not be to use the primary spokesdb.</p> |
| reduce_cost_for_spokes_api | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>reduce_cost_for_spokes_api enables the feature of the same name in Gitmon.</p> |





<a name="github.spokes.types.v1.RequestContext.QualityOfService"></a>

### RequestContext.QualityOfService
QualityOfService defines how Gitmon will apply quotas.

| Name | Number | Description |
| ---- | ------ | ----------- |
| QUALITY_OF_SERVICE_INVALID | 0 | QUALITY_OF_SERVICE_INVALID is the default enum value and should not be used. |
| QUALITY_OF_SERVICE_NO_DELAY | 1 | QUALITY_OF_SERVICE_NO_DELAY forbids Gitmon from delaying or aborting requests. This is only appropriate for user-facing requests where a the client cannot tolerate delays (e.g. when rendering a page on github.com). |
| QUALITY_OF_SERVICE_DELAYABLE | 2 | QUALITY_OF_SERVICE_DELAYABLE is the "normal" way for Gitmon to apply quotas. This means that the request may be delayed or aborted, depending on the state of the quotas and the server's health. |
| QUALITY_OF_SERVICE_FAIL_FAST | 3 | QUALITY_OF_SERVICE_FAIL_FAST means that Gitmon will abort rather than delay responses. This is appropriate for non-urgent work that the caller is OK with retrying later. |


