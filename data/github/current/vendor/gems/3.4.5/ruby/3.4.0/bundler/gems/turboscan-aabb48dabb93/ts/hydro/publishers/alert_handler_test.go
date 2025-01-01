package publishers

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mocks"
)

func TestNewAlertEvent(t *testing.T) {
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockAlertPublisher(mockCtrl)
	handler := NewHydroAlertHandler(publisher)

	uid := ts.UserEID(44)
	te := &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 10,
		EventType:      ts.TimelineEventTypeUnknown,
		UserID:         &uid,
	}
	tool := &ts.Tool{ID: 123, CanonicalName: "CodeQL command-line toolchain"}
	toolVersion := &ts.ToolVersion{ID: 456, ToolID: tool.ID, SemanticVersion: "2.0.1"}
	pa := &ts.PhysicalAlert{
		ID: 17,
		Region: ts.Region{
			StartLine:   6,
			EndLine:     12,
			StartColumn: 1,
			EndColumn:   42,
		},
		Analysis: &ts.Analysis{
			ID:            1,
			CommitOid:     "aaaaa",
			Ref:           []byte("refs/heads/ref1"),
			AnalysisKey:   ".github/workflow/codeql.yml:CodeQL",
			Environment:   ts.AnalysisEnv{},
			Tool:          tool,
			ToolID:        tool.ID,
			ToolVersion:   toolVersion,
			ToolVersionID: toolVersion.ID,
		},
	}
	isFixed := true
	la := &ts.LogicalAlert{
		ID:           18,
		RepositoryID: 1,
		RuleID:       123,
		Number:       34,
		FilePath:     "main.js",
		Rule: &ts.Rule{
			SeverityLevel:    ts.SeverityLevelError,
			SarifIdentifier:  "bar",
			Help:             "Some *rule* **help**",
			ShortDescription: "Something short",
			Tags:             []ts.RuleTag{{Tag: "red"}},
			Tool:             tool,
			ToolID:           tool.ID,
			QueryURI:         "https://github.com/github/ql/tree/main/some-query.ql",
		},
		PhysicalAlerts: []*ts.PhysicalAlert{pa},
		IsFixed:        &isFixed,
	}
	expectedResult, err := serializeResult(*la)
	require.NoError(t, err)

	expected := &tshydro.AlertEvent{
		RepositoryId: 1,
		Event:        tshydro.AlertEvent_UNKNOWN,
		AlertNumber:  int32(34),
		ActorId:      uint32(44),
		Result:       expectedResult,
	}

	publisher.EXPECT().
		AlertEvent(gomock.Any(), expected).
		Return(nil).
		Times(1)
	err = handler.NewAlertEvent(ctx, la, te)
	require.NoError(t, err)

	expected = &tshydro.AlertEvent{
		RepositoryId: 1,
		Event:        tshydro.AlertEvent_ALERT_REOPENED_BY_USER,
		AlertNumber:  int32(34),
		Result:       expectedResult,
	}
	te = &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 10,
		EventType:      ts.TimelineEventTypeAlertReopenedByUser,
	}
	publisher.EXPECT().
		AlertEvent(gomock.Any(), expected).
		Times(1)
	err = handler.NewAlertEvent(ctx, la, te)
	require.NoError(t, err)
}

func TestNewAlertEvent_DeleteEvent(t *testing.T) {
	// The delete event is a bit special because it is the only one that does not
	// require serializing the Result
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockAlertPublisher(mockCtrl)
	handler := NewHydroAlertHandler(publisher)

	uid := ts.UserEID(44)
	te := &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 18,
		EventType:      ts.TimelineEventTypeAlertDeletedByUser,
		UserID:         &uid,
	}
	la := &ts.LogicalAlert{
		ID:           18,
		RepositoryID: 1,
		Number:       34,
	}

	expected := &tshydro.AlertEvent{
		RepositoryId: 1,
		Event:        tshydro.AlertEvent_ALERT_DELETED_BY_USER,
		AlertNumber:  int32(34),
		ActorId:      uint32(44),
		Result:       nil,
	}

	publisher.EXPECT().
		AlertEvent(gomock.Any(), expected).
		Return(nil).
		Times(1)
	err := handler.NewAlertEvent(ctx, la, te)
	require.NoError(t, err)
}

func TestNewAlertEvent_ClosedEvents(t *testing.T) {
	// set up
	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockAlertPublisher(mockCtrl)
	handler := NewHydroAlertHandler(publisher)

	tool := &ts.Tool{ID: 123, CanonicalName: "CodeQL command-line toolchain"}
	toolVersion := &ts.ToolVersion{ID: 456, ToolID: tool.ID, SemanticVersion: "2.0.1"}
	pa := &ts.PhysicalAlert{Analysis: &ts.Analysis{Tool: tool, ToolVersion: toolVersion}}
	isFixed := false
	la := &ts.LogicalAlert{
		Rule:           &ts.Rule{Tool: tool, ToolID: tool.ID},
		PhysicalAlerts: []*ts.PhysicalAlert{pa},
		IsFixed:        &isFixed,
	}
	hydroEventResult, err := serializeResult(*la)
	require.NoError(t, err)

	// expect the hydro event with the alert type 'FIXED' to be published twice (closing an alert as 'outdated' and closing one as 'fixed').
	expectedHydroAlertEvent := &tshydro.AlertEvent{
		RepositoryId: 1,
		Event:        tshydro.AlertEvent_ALERT_CLOSED_BECAME_FIXED,
		Result:       hydroEventResult,
	}

	publisher.EXPECT().
		AlertEvent(gomock.Any(), expectedHydroAlertEvent).
		Times(2)

	// act with a timeline alert that's 'outdated'
	outdatedTimelineEvent := &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 10,
		EventType:      ts.TimelineEventTypeAlertClosedBecameOutdated,
	}
	err = handler.NewAlertEvent(context.Background(), la, outdatedTimelineEvent)
	require.NoError(t, err)

	// act with a timeline event that's 'fixed'
	fixedTimelineEvent := &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 10,
		EventType:      ts.TimelineEventTypeAlertClosedBecameFixed,
	}
	err = handler.NewAlertEvent(context.Background(), la, fixedTimelineEvent)
	require.NoError(t, err)
}
