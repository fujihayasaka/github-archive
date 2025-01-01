package azps2s

// AZP Project Name *should* always be this
const AZPDefaultProjectName = "PipelinesProject"
const PipelineScaleUnitType = "VsService:0000005a-0000-8888-8000-000000000000"
const ArtifactCacheScaleUnitType = "VsService:0000006d-0000-8888-8000-000000000000"
const RunnerScaleUnitType = "VsService:0000006f-0000-8888-8000-000000000000"

// CreateOrganizationResponse is the resonse when an org is created.
type createOrganizationResponse struct {
	Organization    organization `json:"organization"`
	Project         project      `json:"project"`
	PipelineID      int64        `json:"pipelineId"`
	Application     application  `json:"application"`
	OperationURL    string       `json:"url"`
	OperationStatus string       `json:"status"`
	Links           *links       `json:"_links"`
}

// Organization is the information about the created organization.
type organization struct {
	Name       string                  `json:"name"`
	ID         string                  `json:"id"`
	Properties map[string]hostInstance `json:"properties"`
}

type hostInstance struct {
	ValueType string `json:"$type"`
	Value     string `json:"$value"`
}

// Project correlates to a project.
type project struct {
	Name string `json:"name"`
	ID   string `json:"id"`
}

// Application is the application for the organization.
type application struct {
	ClientID string `json:"clientId"`
}

// Links return links to pipelines and runs for the organization.
type links struct {
	Pipeline *pipelineLink `json:"pipeline"`
}

// PipelineLink is a link to directly accessing the pipeline configuration
type pipelineLink struct {
	URL string `json:"href"`
}

type org struct {
	Name            string `json:"name"`
	PreferredRegion string `json:"preferredRegion"`
}

type pipeline struct {
	Repository string `json:"repository"`
}
type pubKey struct {
	Modulus  string `json:"modulus"`
	Exponent string `json:"exponent"`
}
type inputs struct {
	PublicKey pubKey `json:"publicKey"`
}
type requestBody struct {
	ProviderID                  string   `json:"providerId"`
	Organization                org      `json:"organization"`
	Pipeline                    pipeline `json:"pipeline"`
	ApplicationInputs           inputs   `json:"applicationInputs"`
	GitHubResourceType          string   `json:"githubResourceType"`
	GitHubResourceID            int64    `json:"githubResourceId"`
	GitHubResourceGlobalID      string   `json:"githubResourceGlobalId"`
	GitHubResourceOwnerType     string   `json:"githubResourceOwnerType,omitempty"`
	GitHubResourceOwnerID       int64    `json:"githubResourceOwnerId,omitempty"`
	GitHubResourceOwnerGlobalID string   `json:"githubResourceOwnerGlobalId,omitempty"`
	PlanSKU                     string   `json:"planSku,omitempty"`
	BillingOwnerCreatedAt       string   `json:"billingOwnerCreatedAt,omitempty"`
}
