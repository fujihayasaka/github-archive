package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestUserConversion(t *testing.T) {
	name := "monalisa"
	userURL := "http//github.test/monalisa"
	orgID := "test-org"
	email := "monalisa@mail.com"

	u := &User{
		Type:      "user",
		URL:       userURL,
		AvatarURL: "unused",
		Login:     "unused",
		Name:      name,
		Bio:       "unused",
		Company:   "unused",
		Website:   "unused",
		Location:  "unused",
		Emails: []Email{
			{
				Address:  email,
				Primary:  false,
				Verified: false,
			},
			{
				Address:  "only-first-email-is-used",
				Primary:  true,
				Verified: false,
			},
		},
		SocialAccounts: []SocialAccount{
			{
				Provider: "unused",
				URL:      "unused",
			},
		},
		BillingPlan: "unused", CreatedAt: time.Time{}}

	expected := &v1.Mannequin{
		ResourceId:    userURL,
		OrgResourceId: orgID,
		ProfileName:   name,
		Email:         email,
	}
	v1m, err := u.ToV1Mannequin(orgID)
	require.NoError(t, err)
	require.Equal(t, expected, v1m)
}
