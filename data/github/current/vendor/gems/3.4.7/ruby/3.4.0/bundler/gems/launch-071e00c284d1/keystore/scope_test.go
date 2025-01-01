package keystore

import (
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/types"
)

const (
	testEnvironment  = "testing"
	testOrganization = "Acme Inc."
)

func TestScope(t *testing.T) {
	suite.Run(t, new(scopeTestSuite))
}

type scopeTestSuite struct {
	suite.Suite
}

func (s *scopeTestSuite) TestNewScopeCorrectlyReturnsScope() {
	testRepoID := types.GlobalID("test_repo_id")
	scope, err := NewScope(testEnvironment, testOrganization)
	s.NotNil(scope)
	s.NoError(err)
	s.Equal(testEnvironment, scope.Environment)
	s.Equal(testOrganization, scope.Organization)
	s.Equal(testRepoID, types.GlobalID("test_repo_id"))
}

func (s *scopeTestSuite) TestScopeErrorsWithEmptyEnv() {
	scope, err := NewScope("", testOrganization)
	s.Nil(scope)
	s.Error(err)
}

func (s *scopeTestSuite) TestScopeErrorsWithEmptyOrg() {
	scope, err := NewScope(testEnvironment, "")
	s.Nil(scope)
	s.Error(err)
}
