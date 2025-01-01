package entitiesv1

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGitHubEntityHierarchy_IsEmpty(t *testing.T) {
	h := GitHubEntityHierarchy{}
	assert.True(t, h.IsEmpty())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}}
	assert.False(t, h.IsEmpty())

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.False(t, h.IsEmpty())

	h = GitHubEntityHierarchy{RepositoryId: &Identity{GlobalId: "R_repo"}}
	assert.False(t, h.IsEmpty())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}, RepositoryId: &Identity{GlobalId: "R_repo"}}
	assert.False(t, h.IsEmpty())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.False(t, h.IsEmpty())

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}, RepositoryId: &Identity{GlobalId: "R_repo"}}
	assert.False(t, h.IsEmpty())
}

func TestGitHubEntityHierarchy_Parent(t *testing.T) {

	var nilGitHubEntityHierarchy *GitHubEntityHierarchy = nil
	assert.Nil(t, nilGitHubEntityHierarchy.Parent())

	h := GitHubEntityHierarchy{}
	assert.Nil(t, h.Parent())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}, RepositoryId: &Identity{GlobalId: "R_rep"}}
	expected := &GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Equal(t, expected.String(), h.Parent().String())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}}
	expected = &GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}}
	assert.Equal(t, expected.String(), h.Parent().String())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}}
	assert.Nil(t, h.Parent())

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}, RepositoryId: &Identity{GlobalId: "R_rep"}}
	expected = &GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Equal(t, expected.String(), h.Parent().String())

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Nil(t, h.Parent())

	h = GitHubEntityHierarchy{RepositoryId: &Identity{GlobalId: "R_rep"}}
	assert.Nil(t, h.Parent())
}

func TestGitHubEntityHierarchy_GetBillingOwnerID(t *testing.T) {

	var nilGitHubEntityHierarchy *GitHubEntityHierarchy = nil
	assert.Nil(t, nilGitHubEntityHierarchy.GetBillingOwnerID())

	h := GitHubEntityHierarchy{}
	assert.Nil(t, h.GetBillingOwnerID())

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, RepositoryId: &Identity{GlobalId: "R_rep"}, OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Equal(t, "E_ent", h.GetBillingOwnerID().GlobalId)

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}, OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Equal(t, "E_ent", h.GetBillingOwnerID().GlobalId)

	h = GitHubEntityHierarchy{EnterpriseId: &Identity{GlobalId: "E_ent"}}
	assert.Equal(t, "E_ent", h.GetBillingOwnerID().GlobalId)

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}, RepositoryId: &Identity{GlobalId: "R_rep"}}
	assert.Equal(t, "O_org", h.GetBillingOwnerID().GlobalId)

	h = GitHubEntityHierarchy{OrganizationId: &Identity{GlobalId: "O_org"}}
	assert.Equal(t, "O_org", h.GetBillingOwnerID().GlobalId)

	h = GitHubEntityHierarchy{RepositoryId: &Identity{GlobalId: "R_repo"}}
	assert.Nil(t, h.GetBillingOwnerID())
}
