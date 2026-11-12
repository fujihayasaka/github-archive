package eventstest

import (
	cs_pb "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
)

func entitySuggestedFix() *cs_pb.AlertsAssignment_Alert_SuggestedFix {
	files := []*cs_pb.AlertsAssignment_Alert_SuggestedFixFile{
		{
			FilePath:    "path/to/file",
			DiffContent: []byte("diff content"),
		},
	}

	return &cs_pb.AlertsAssignment_Alert_SuggestedFix{
		Files: files,
	}
}

func EntityCodeScanningAlert() *cs_pb.AlertsAssignment_Alert {
	return &cs_pb.AlertsAssignment_Alert{
		AlertNumber:  1,
		SuggestedFix: entitySuggestedFix(),
	}
}

func EntitiesAlertsAssignmentAssigneeCopilot() *cs_pb.AlertsAssignment {
	return &cs_pb.AlertsAssignment{
		Repository: EntitiesRepository(),
		Actor:      EntitiesUserWriter(),
		CodeScanningAlerts: []*cs_pb.AlertsAssignment_Alert{
			EntityCodeScanningAlert(),
		},
		Assignees: []*entities.User{EntitiesUserCopilot()},
	}
}

func EntitiesAlertsAssignmentActorReader() *cs_pb.AlertsAssignment {
	return &cs_pb.AlertsAssignment{
		Repository: EntitiesRepository(),
		Actor:      EntitiesUserReader(),
		CodeScanningAlerts: []*cs_pb.AlertsAssignment_Alert{
			EntityCodeScanningAlert(),
		},
		Assignees: []*entities.User{EntitiesUserCopilot()},
	}
}

func EntitiesAlertsAssignmentAssigneeReader() *cs_pb.AlertsAssignment {
	return &cs_pb.AlertsAssignment{
		Repository: EntitiesRepository(),
		Actor:      EntitiesUserReader(),
		CodeScanningAlerts: []*cs_pb.AlertsAssignment_Alert{
			EntityCodeScanningAlert(),
		},
		Assignees: []*entities.User{EntitiesUserReader()},
	}
}
