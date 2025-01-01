package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func createTestProject(t *testing.T) *Project {
	t.Helper()

	return &Project{
		URL:       "https://github.test/test-org/test-repo/projects/1",
		CreatedAt: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
		UpdatedAt: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
		ClosedAt:  time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
		Columns: []Column{
			{
				Position:  1,
				Name:      "column1",
				Color:     "color1",
				CreatedAt: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
				UpdatedAt: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
				HiddenAt:  time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
				Purpose:   "todo",
				Workflows: []Workflow{
					{
						Creator:     "http://github.test/monalisa",
						LastUpdater: "http://github.test/monalisa",
						CreatedAt:   time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
						UpdatedAt:   time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
						TriggerType: "issue_closed",
						Actions: []Action{
							{
								Creator:     "http://github.test/monalisa",
								LastUpdater: "http://github.test/monalisa",
								CreatedAt:   time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
								UpdatedAt:   time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC),
							},
						},
					},
				},
			},
		},
	}
}

func TestProjectConversion(t *testing.T) {
	p := createTestProject(t)

	expected := &v1.Project{
		ResourceId:        p.URL,
		Name:              p.Name,
		Number:            p.Number,
		OwnerResourceId:   p.OwnerURL,
		OwnerType:         v1.OwnerType_OWNER_TYPE_REPOSITORY,
		CreatorResourceId: p.CreatorURL,
		Body:              p.Body,
		IsPublic:          p.IsPublic,
		CreatedAt:         toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
		UpdatedAt:         toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
		ClosedAt:          toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
	}

	v1p := p.ToV1Project()
	require.Equal(t, expected, v1p)
}

func TestExtractV1ProjectColumns(t *testing.T) {
	p := createTestProject(t)

	expected := []*v1.ProjectColumn{
		{
			ResourceId:        "https://github.test/test-org/test-repo/projects/1/columns/1",
			Name:              "column1",
			Color:             "color1",
			CreatedAt:         toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
			UpdatedAt:         toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
			Purpose:           "todo",
			Position:          1,
			HiddenAt:          toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
			ProjectResourceId: "https://github.test/test-org/test-repo/projects/1",
			Workflows: []*v1.ProjectWorkflow{
				{
					CreatorResourceId:     "http://github.test/monalisa",
					TriggerType:           "issue_closed",
					CreatedAt:             toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
					LastUpdaterResourceId: "http://github.test/monalisa",
					UpdatedAt:             toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
					Actions: []*v1.ProjectWorkflowAction{
						{
							CreatorResourceId:     "http://github.test/monalisa",
							CreatedAt:             toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
							LastUpdaterResourceId: "http://github.test/monalisa",
							UpdatedAt:             toTimestamp(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
						},
					},
				},
			},
		},
	}

	columns := p.extractV1ProjectColumns()
	require.Equal(t, expected, columns)
}

func TestProjectExtractOwnerType(t *testing.T) {
	type testCase struct {
		p        *Project
		expected v1.OwnerType
	}
	cases := map[string]*testCase{
		"EmptyProjectInvalid": {
			p:        &Project{},
			expected: v1.OwnerType_OWNER_TYPE_INVALID,
		},
		"ValidHttpOrg": {
			p: &Project{
				URL: "http://github.test/test-org/projects/5",
			},
			expected: v1.OwnerType_OWNER_TYPE_ORGANIZATION,
		},
		"ValidOrg": {
			p: &Project{
				URL: "https://github.test/test-org/projects/5",
			},
			expected: v1.OwnerType_OWNER_TYPE_ORGANIZATION,
		},
		"ValidUser": {
			p: &Project{
				URL: "https://github.test/users/monalisa/projects/5",
			},
			expected: v1.OwnerType_OWNER_TYPE_USER,
		},
		"ValidRepository": {
			p: &Project{
				URL: "https://github.test/test-org/test-repo/projects/5",
			},
			expected: v1.OwnerType_OWNER_TYPE_REPOSITORY,
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			ot := tc.p.extractOwnerType()
			require.Equal(t, tc.expected, ot)
		})
	}
}
