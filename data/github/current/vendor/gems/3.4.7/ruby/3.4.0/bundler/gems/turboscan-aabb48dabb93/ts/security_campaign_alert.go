package ts

// SecurityCampaignAlertID represents the ID used within a SecurityCampaignAlert
type SecurityCampaignAlertID uint64

// SecurityCampaignAlert represents that an alert is part of a security campaign.
// It is possible for multiple alerts to be present in the same campaign, and for
// the same alert to be present in multiple campaigns.
type SecurityCampaignAlert struct {
	BaseModel
	ID                 SecurityCampaignAlertID `verify:"ignore"`
	RepositoryID       RepositoryEID
	LogicalAlertID     LogicalAlertID
	SecurityCampaignID SecurityCampaignEID
}
