package identity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestIsPersonalAccessToken(t *testing.T) {
	// Define the time for testing purposes
	currentTime := time.Now()

	tests := []struct {
		context  *OauthAccessContext
		expected bool
	}{
		// Test case where Application is nil
		{
			context: &OauthAccessContext{
				Application: nil,
				CreatedAt:   currentTime,
			},
			expected: true,
		},
		// Test case where Application ID matches the PersonalAccessTokenApplicationID
		{
			context: &OauthAccessContext{
				Application: &ApplicationContext{
					ID:        PersonalAccessTokenApplicationID,
					Type:      ApplicationTypeOauthApplication,
					OwnerID:   123,
					OwnerType: ApplicationOwnerTypeUser,
				},
				CreatedAt: currentTime,
			},
			expected: true,
		},
		// Test case where Application ID does not match the PersonalAccessTokenApplicationID
		{
			context: &OauthAccessContext{
				Application: &ApplicationContext{
					ID:        12345, // Non-matching ID
					Type:      ApplicationTypeOauthApplication,
					OwnerID:   456,
					OwnerType: ApplicationOwnerTypeOrganization,
				},
				CreatedAt: currentTime,
			},
			expected: false,
		},
	}

	for _, test := range tests {
		result := test.context.IsPersonalAccessToken()
		assert.Equal(t, test.expected, result)
	}
}
