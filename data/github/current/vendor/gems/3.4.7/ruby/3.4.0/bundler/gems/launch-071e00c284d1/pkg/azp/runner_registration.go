package azp

type RunnerRegistrationToken struct {
	HostURL string `json:"ServerUrl"`
	Token   string `json:"Token"`
}

type RunnerRegistrationCredentials struct {
	HostURL string
	Scheme  string                   `json:"scheme"`
	Data    *RunnerRegistrationToken `json:"data"`
}

// / These fields are added to the token request and are as embedded as claims in the returned token
// / These fields are always sent in the next global id format. See: https://github.com/github/github/pull/223594.
type RunnerAdminTokenMetadata struct {
	OwnerID        string `json:"ownerId"`
	BillingOwnerID string `json:"billingOwnerId"`
	TenantSlug     string `json:"tenantSlug"`
}

func (rrc *RunnerRegistrationCredentials) IsValid() bool {
	return rrc != nil && rrc.Scheme != "" && rrc.Data != nil && rrc.Data.Token != ""
}
