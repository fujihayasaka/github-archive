package identity

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseActorType(t *testing.T) {
	tests := []struct {
		input    string
		expected ActorType
		err      bool
	}{
		{"User", ActorTypeUser, false},
		{"Bot", ActorTypeBot, false},
		{"Integration", ActorTypeIntegration, false},
		{"OauthApplication", ActorTypeOauthApplication, false},
		{"Repository", ActorTypeRepository, false},
		{"InvalidType", "", true}, // Should return an error
	}

	for _, test := range tests {
		result, err := ParseActorType(test.input)
		if test.err {
			assert.NotNil(t, err)
		} else {
			assert.Nil(t, err)
		}
		assert.Equal(t, test.expected, result)
	}
}
