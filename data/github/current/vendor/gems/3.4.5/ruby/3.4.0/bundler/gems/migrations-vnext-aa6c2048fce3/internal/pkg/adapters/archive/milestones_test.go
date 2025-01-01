package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestMilestoneConversion(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	m := &Milestone{
		Type:        "type",
		URL:         "url",
		Repository:  "repo",
		User:        "user",
		Title:       "title",
		Description: "desc",
		State:       "state",
		DueOn:       someTime,
		CreatedAt:   someTime,
		UpdatedAt:   someTime,
		ClosedAt:    someTime,
	}

	issues := []string{"1", "2", "3"}
	milestoneToIssue := map[string][]string{
		m.URL: issues,
	}

	expected := &v1.Milestone{
		ResourceId:       m.URL,
		Title:            m.Title,
		UserResourceId:   m.User,
		Description:      m.Description,
		State:            m.State,
		DueOn:            toTimestamp(someTime),
		CreatedAt:        toTimestamp(someTime),
		UpdatedAt:        toTimestamp(someTime),
		ClosedAt:         toTimestamp(someTime),
		IssueResourceIds: issues,
	}

	v1m, err := m.ToV1Milestone(milestoneToIssue)
	require.NoError(t, err)
	require.Equal(t, expected, v1m)

	var ms Milestones
	ms = append(ms, *m)
	// Add another separate milestone
	m2 := &Milestone{
		Type:        "type",
		URL:         "url2",
		Repository:  "repo",
		User:        "user",
		Title:       "title",
		Description: "desc",
		State:       "state",
		DueOn:       someTime,
		CreatedAt:   someTime,
		UpdatedAt:   someTime,
		ClosedAt:    someTime,
	}
	milestoneToIssue[m2.URL] = []string{"7", "8"}
	ms = append(ms, *m2)
	expected2 := &v1.Milestone{
		ResourceId:       m2.URL,
		Title:            m2.Title,
		UserResourceId:   m2.User,
		Description:      m2.Description,
		State:            m.State,
		DueOn:            toTimestamp(someTime),
		CreatedAt:        toTimestamp(someTime),
		UpdatedAt:        toTimestamp(someTime),
		ClosedAt:         toTimestamp(someTime),
		IssueResourceIds: []string{"7", "8"},
	}
	v1ms, err := ms.ToV1Milestones(milestoneToIssue)
	require.NoError(t, err)
	require.Equal(t, []*v1.Milestone{expected, expected2}, v1ms)
}
