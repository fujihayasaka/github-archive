package queue

const (
	QueueName_ProvisionImageVersion = "ims_provision_image_version"
	QueueName_DeleteImageVersion    = "ims_delete_image_version"
	QueueName_ProvisionCleanup      = "ims_provision_cleanup"
)

type ProvisionImageVersionJobPayload struct {
	ImageVersionId      uint64 `json:"imageVersionId"`
	SourceVhdUrlEncoded []byte `json:"sourceVhdUrlEncoded"`
	SourceVhdUrlSalt    []byte `json:"sourceVhdUrlsalt"`
}

type DeleteImageVersionJobPayload struct {
	ImageVersionId uint64 `json:"imageVersionId"`
}

type ProvisionCleanupJobPayload struct {
	ImageVersionId uint64 `json:"imageVersionId"`
}
