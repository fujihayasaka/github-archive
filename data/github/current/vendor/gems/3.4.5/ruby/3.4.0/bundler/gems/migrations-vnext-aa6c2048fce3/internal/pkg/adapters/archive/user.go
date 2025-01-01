package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	// Email represents a user's email address.
	Email struct {
		Address  string `json:"address"`
		Primary  bool   `json:"primary"`
		Verified bool   `json:"verified"`
	}

	// SocialAccount represents a user's social account.
	SocialAccount struct {
		Provider string `json:"provider"`
		URL      string `json:"url"`
	}

	// User represents a user.
	User struct {
		Type           string          `json:"type"`
		URL            string          `json:"url"`
		AvatarURL      string          `json:"avatar_url"`
		Login          string          `json:"login"`
		Name           string          `json:"name"`
		Bio            string          `json:"bio"`
		Company        string          `json:"company"`
		Website        string          `json:"website"`
		Location       string          `json:"location"`
		Emails         []Email         `json:"emails"`
		SocialAccounts []SocialAccount `json:"social_accounts"`
		BillingPlan    string          `json:"billing_plan"`
		CreatedAt      time.Time       `json:"created_at"`
	}
)

// ToV1Mannequin converts a User to a v1.Mannequin.
func (u User) ToV1Mannequin(orgID string) (*v1.Mannequin, error) {
	req := &v1.Mannequin{
		ResourceId:    u.URL,
		OrgResourceId: orgID,
		ProfileName:   u.Name,
	}
	if len(u.Emails) > 0 {
		req.Email = u.Emails[0].Address
	}
	return req, nil
}
