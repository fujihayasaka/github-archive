package archive

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestTeamConversion(t *testing.T) {
	team := &Team{
		URL:        "http://github.test/orgs/test-org/teams/a-team",
		ParentTeam: "",
		Name:       "A-Team",
		Privacy:    "secret",
	}
	expected := &v1.Team{
		ResourceId:           team.URL,
		ParentTeamResourceId: team.ParentTeam,
		Name:                 team.Name,
		Visibility:           team.Privacy,
	}

	v1t, err := team.ToV1Team()
	require.NoError(t, err)
	require.Equal(t, expected, v1t)
}
