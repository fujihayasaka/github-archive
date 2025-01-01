package customerlabels

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewCustomerLabeler(t *testing.T) {
	labeler, err := NewCustomerLabeler("github", "")
	require.NoError(t, err)

	github := labeler.LabelFor("github", "")
	require.Equal(t, "github", github)
}

func Test_MultipleOrgs(t *testing.T) {
	labeler, err := NewCustomerLabeler("github,org1, org2", "")
	require.NoError(t, err)

	label := labeler.LabelFor("github", "")
	require.Equal(t, "github", label)

	label = labeler.LabelFor("org1", "")
	require.Equal(t, "top100", label)

	label = labeler.LabelFor("org2", "")
	require.Equal(t, "top100", label)
}

func Test_CaseInsensitive(t *testing.T) {
	labeler, err := NewCustomerLabeler("GitHub,orG1, Org2", "")
	require.NoError(t, err)

	label := labeler.LabelFor("github", "")
	require.Equal(t, "github", label)

	label = labeler.LabelFor("Github", "")
	require.Equal(t, "github", label)

	label = labeler.LabelFor("org1", "")
	require.Equal(t, "top100", label)

	label = labeler.LabelFor("org2", "")
	require.Equal(t, "top100", label)
}

func Test_No_labels(t *testing.T) {
	labeler, err := NewCustomerLabeler("", "")
	require.NoError(t, err)

	randomOrg := labeler.LabelFor("random_org", "")
	require.Equal(t, "", randomOrg)
}

func Test_Noop_labeler(t *testing.T) {
	labeler := NewNoopCustomerLabeler()

	github := labeler.LabelFor("github", "")
	require.Equal(t, "", github)
}

func Test_EnterpriseLabel(t *testing.T) {
	labeler, err := NewCustomerLabeler("getsentry", "amazon,zendesk")
	require.NoError(t, err)

	// enterprise is in the fourNinesEnterprises
	label := labeler.LabelFor("random_org", "amazon")
	require.Equal(t, "amazon", label)

	// if enterprise == same as org, and is part of top 100
	label = labeler.LabelFor("getsentry", "getsentry")
	require.Equal(t, Top100Label, label)

	// if enterprise == same as org, and is not part of top 100, but part of fourNinesEnterprises
	label = labeler.LabelFor("zendesk", "zendesk")
	require.Equal(t, "zendesk", label)

	// if enterprise == same as org, and is not part of top 100, and not part of fourNinesEnterprises
	label = labeler.LabelFor("random_org", "random_org")
	require.Equal(t, "", label)
}
