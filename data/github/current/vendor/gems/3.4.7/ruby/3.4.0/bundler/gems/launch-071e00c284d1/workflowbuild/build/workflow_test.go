package build

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/types"
)

func TestMapActionsBillingPlanOwner_PlanNameAsSKU(t *testing.T) {
	planOwner := types.WorkflowInvocationPlanOwner{
		Name:     "owner-name",
		GlobalID: types.GlobalID("E_kgAB"),
		PlanName: "enterprise",
		Type:     "Organization",
	}

	owner := types.WorkflowInvocationOwner{
		GlobalID: planOwner.GlobalID,
		Name:     planOwner.Name,
	}
	billingPlanOwner, err := mapActionsBillingPlanOwner(&types.RepositoryTenants{}, owner, planOwner)

	require.NoError(t, err)
	assert.Equal(t, owner.GlobalID, billingPlanOwner.RepositoryOwnerID)
	assert.Equal(t, "enterprise", billingPlanOwner.PlanSKU)
	assert.Equal(t, "owner-name", billingPlanOwner.RepositoryOwnerName)
}

func TestMapActionsBillingPlanOwner_TenantInfo(t *testing.T) {
	planOwner := types.WorkflowInvocationPlanOwner{
		Name:     "owner-name",
		GlobalID: types.GlobalID("E_kgAB"),
		PlanName: "enterprise",
		Type:     "Organization",
	}

	owner := types.WorkflowInvocationOwner{
		GlobalID: planOwner.GlobalID,
		Name:     planOwner.Name,
	}
	billingPlanOwner, err := mapActionsBillingPlanOwner(&types.RepositoryTenants{
		OwnerTenantID:              "owner-tenant-id",
		OwnerTenantName:            "owner-tenant-name",
		OwnerTenantURL:             "owner-tenant-url",
		BillingPlanOwnerTenantID:   "billing-plan-owner-tenant-id",
		BillingPlanOwnerTenantName: "billing-plan-owner-tenant-name",
		BillingPlanOwnerTenantURL:  "billing-plan-owner-tenant-url",
	}, owner, planOwner)

	require.NoError(t, err)
	assert.Equal(t, owner.GlobalID, billingPlanOwner.RepositoryOwnerID)
	assert.Equal(t, "billing-plan-owner-tenant-id", billingPlanOwner.TenantID)
	assert.Equal(t, "billing-plan-owner-tenant-name", billingPlanOwner.TenantName)
	assert.Equal(t, "billing-plan-owner-tenant-url", billingPlanOwner.TenantURL)
	assert.Equal(t, "owner-tenant-id", billingPlanOwner.OrganizationTenantID)
	assert.Equal(t, "owner-tenant-name", billingPlanOwner.OrganizationTenantName)
	assert.Equal(t, "owner-tenant-url", billingPlanOwner.OrganizationTenantURL)
}

func TestMapActionsBillingPlanOwner_InvalidGlobalID(t *testing.T) {
	planOwner := types.WorkflowInvocationPlanOwner{
		Name:     "owner-name",
		GlobalID: types.GlobalID("global-id-in-the-wrong format"),
		PlanName: "enterprise",
		Type:     "Organization",
	}

	owner := types.WorkflowInvocationOwner{
		GlobalID: planOwner.GlobalID,
		Name:     planOwner.Name,
	}
	_, err := mapActionsBillingPlanOwner(&types.RepositoryTenants{}, owner, planOwner)

	assert.Error(t, err)
	assert.ErrorContains(t, err, "failed to decode billing plan owner id")
}

func TestWorkflowBuild_WorkflowReferencedFiles(t *testing.T) {
	testCases := []struct {
		desc             string
		workflowFullPath string
		checkoutRef      string
		resolved         []types.ResolvedFile
		referenced       map[string]ReferencedFile
		out              []wfparser.WorkflowReferencedFile
	}{
		{
			desc: "empty returns empty",
			out:  []wfparser.WorkflowReferencedFile{},
		},
		{
			desc: "one resolved file returns",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
		},
		{
			desc: "referenced file's NWO is preferred over the resolved file's NWO",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			referenced: map[string]ReferencedFile{
				".github/workflows/test.yml": {
					RepositoryNWO: types.RepositoryFullName{Owner: "My-Org", Name: "My-Repo"},
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "My-Org/My-Repo",
				},
			},
		},
		{
			desc: "required workflow file returns",
			resolved: []types.ResolvedFile{
				{
					Path:          "required/123456/.github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
					IsRequired:    true,
				},
			},
		},
		{
			desc:             "does not coalesce root file ref",
			workflowFullPath: ".github/workflows/test.yml",
			checkoutRef:      "refs/heads/my-branch",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
		},
	}
	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			b := WorkflowBuild{
				WorkflowFilePath: tc.workflowFullPath,
				CheckoutRef:      types.GitRef(tc.checkoutRef),
				ResolvedFiles:    tc.resolved,
				ReferencedFiles:  tc.referenced,
			}
			out := b.WorkflowReferencedFiles(false)
			assert.Equal(t, tc.out, out)
		})
	}
}

func TestWorkflowBuild_WorkflowReferencedFiles_CoalesceRootFileRef(t *testing.T) {
	testCases := []struct {
		desc             string
		workflowFullPath string
		checkoutRef      string
		resolved         []types.ResolvedFile
		referenced       map[string]ReferencedFile
		out              []wfparser.WorkflowReferencedFile
	}{
		{
			desc: "empty returns empty",
			out:  []wfparser.WorkflowReferencedFile{},
		},
		{
			desc: "one resolved file returns",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
		},
		{
			desc: "referenced file's NWO is preferred over the resolved file's NWO",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			referenced: map[string]ReferencedFile{
				".github/workflows/test.yml": {
					RepositoryNWO: types.RepositoryFullName{Owner: "My-Org", Name: "My-Repo"},
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "My-Org/My-Repo",
				},
			},
		},
		{
			desc: "required workflow file returns",
			resolved: []types.ResolvedFile{
				{
					Path:          "required/123456/.github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/main",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
					IsRequired:    true,
				},
			},
		},
		{
			desc:             "coalesce root file ref",
			workflowFullPath: ".github/workflows/test.yml",
			checkoutRef:      "refs/heads/my-branch",
			resolved: []types.ResolvedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
				{
					Path:          "my-org/my-repo/.github/workflows/deploy.yml@abc123",
					Text:          "some-text-2",
					Ref:           "",
					SHA:           "abc123",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			referenced: map[string]ReferencedFile{
				"my-org/my-repo/.github/workflows/deploy.yml@abc123": {
					RepositoryNWO: types.RepositoryFullName{Owner: "My-Org", Name: "My-Repo"},
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "refs/heads/my-branch",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
				{
					Path:          "my-org/my-repo/.github/workflows/deploy.yml@abc123",
					Text:          "some-text-2",
					Ref:           "",
					SHA:           "abc123",
					RepositoryNwo: "My-Org/My-Repo",
				},
			},
		},
		{
			desc:             "does not coalesce root file ref for required workflows",
			workflowFullPath: "required/my-org/.github/workflows/test.yml",
			checkoutRef:      "refs/heads/my-branch",
			resolved: []types.ResolvedFile{
				{
					Path:          "required/my-org/.github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
			out: []wfparser.WorkflowReferencedFile{
				{
					IsRequired:    true,
					Path:          ".github/workflows/test.yml",
					Text:          "some-text",
					Ref:           "",
					SHA:           "bbcc",
					RepositoryNwo: "my-org/my-repo",
				},
			},
		},
	}
	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			b := WorkflowBuild{
				WorkflowFilePath: tc.workflowFullPath,
				CheckoutRef:      types.GitRef(tc.checkoutRef),
				ResolvedFiles:    tc.resolved,
				ReferencedFiles:  tc.referenced,
			}
			out := b.WorkflowReferencedFiles(true)
			assert.Equal(t, tc.out, out)
		})
	}
}
