package tokenauth

import (
	"testing"

	"github.com/stretchr/testify/suite"
)

type RunnerClaimsSuite struct {
	suite.Suite
}

func TestRunnerClaims(t *testing.T) {
	suite.Run(t, new(RunnerClaimsSuite))
}

func (s *RunnerClaimsSuite) Test_ContainsScopeValue() {
	cases := []struct {
		name             string
		testRunnerClaims *runnerClaims
		testScope        string
		testValue        string
		expected         bool
	}{
		{
			name: "found claims",
			testRunnerClaims: &runnerClaims{
				Scopes: "test.Scope:123:456",
			},
			testScope: "test.Scope",
			testValue: "123:456",
			expected:  true,
		},
		{
			name: "found claims multiple scopes",
			testRunnerClaims: &runnerClaims{
				Scopes: "different.Scope test.Scope:123:456",
			},
			testScope: "test.Scope",
			testValue: "123:456",
			expected:  true,
		},
		{
			name: "different claims",
			testRunnerClaims: &runnerClaims{
				Scopes: "test.Scope:123:456",
			},
			testScope: "test.Scope",
			testValue: "456:123",
			expected:  false,
		},
		{
			name: "no claims",
			testRunnerClaims: &runnerClaims{
				Scopes: "",
			},
			testScope: "test.Scope",
			testValue: "456:123",
			expected:  false,
		},
		{
			name: "different scopes",
			testRunnerClaims: &runnerClaims{
				Scopes: "test.Scope:123:456",
			},
			testScope: "test.NA",
			testValue: "456:123",
			expected:  false,
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			actual := c.testRunnerClaims.containsScopeValue(c.testScope, c.testValue)

			s.Equal(c.expected, actual)
		})
	}
}
