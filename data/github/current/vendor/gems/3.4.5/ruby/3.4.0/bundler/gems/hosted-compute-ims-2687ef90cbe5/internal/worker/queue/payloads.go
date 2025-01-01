package queue

const (
	QueueName_ProvisionImageVersion = "ims_provision_image_version"
	QueueName_DeleteImageDefinition = "ims_delete_image_definition"
	QueueName_DeleteImageVersion    = "ims_delete_image_version"
	QueueName_ProvisionCleanup      = "ims_provision_cleanup"
)

var QueueNames = []string{
	QueueName_ProvisionImageVersion,
	QueueName_DeleteImageDefinition,
	QueueName_DeleteImageVersion,
	QueueName_ProvisionCleanup,
}

type ProvisionImageVersionJobPayload struct {
	ImageVersionId      uint64 `json:"imageVersionId"`
	SourceVhdUrlEncoded []byte `json:"sourceVhdUrlEncoded"`
	SourceVhdUrlSalt    []byte `json:"sourceVhdUrlsalt"`
	WorkflowOwnerId     string `json:"workflowOwnerId"`
}

type DeleteImageDefinitionJobPayload struct {
	ImageDefinitionId uint64 `json:"imageDefinitionId"`
}

type DeleteImageVersionJobPayload struct {
	ImageVersionId uint64 `json:"imageVersionId"`
}

type ProvisionCleanupJobPayload struct {
	ImageVersionId uint64 `json:"imageVersionId"`
}
