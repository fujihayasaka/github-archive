package checks

import (
	"time"

	"github.com/golang/protobuf/ptypes"

	"github.com/github/launch/pkg/azp"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

var (
	timeAStarted   = time.Date(2021, 9, 10, 0, 0, 0, 0, time.UTC)
	timeACompleted = time.Date(2021, 9, 10, 0, 0, 5, 0, time.UTC)

	timeBStarted   = time.Date(2021, 9, 10, 0, 0, 5, 10, time.UTC)
	timeBCompleted = time.Date(2021, 9, 10, 0, 0, 15, 10, time.UTC)

	timeCStarted = time.Date(2021, 9, 10, 0, 0, 15, 10, time.UTC)
)

func mockActionsSteps() []*azp.ChangeIDResponseSteps {
	checkStepLogA := azp.ChangeIDResponseStepLog{
		ID:        1,
		URL:       "",
		LineCount: 1,
	}

	checkStepLogB := azp.ChangeIDResponseStepLog{
		ID:        2,
		URL:       "",
		LineCount: 1,
	}

	return []*azp.ChangeIDResponseSteps{
		{
			ID:          "85CF761C-A106-41A0-A5E2-F45F57ACA3DF",
			Name:        "StepA",
			Status:      azptypes.StatusCompleted,
			Conclusion:  azptypes.ResultSucceeded,
			StartedAt:   &timeAStarted,
			CompletedAt: &timeACompleted,
			Log:         &checkStepLogA,
			ChangeID:    0,
			Number:      1,
		},
		{
			ID:          "6FC0792B-8713-4F3F-8FFD-7A1946577871",
			Name:        "StepB",
			Status:      azptypes.StatusCompleted,
			Conclusion:  azptypes.ResultFailed,
			StartedAt:   &timeBStarted,
			CompletedAt: &timeBCompleted,
			Log:         &checkStepLogB,
			ChangeID:    1,
			Number:      2,
		},
		{
			ID:          "11A0E8E3-E674-4A3C-90AA-D8251CB417CA",
			Name:        "StepC",
			Status:      azptypes.StatusInProgress,
			Conclusion:  "",
			StartedAt:   &timeCStarted,
			CompletedAt: nil,
			Log:         nil,
			ChangeID:    1,
			Number:      3,
		},
		{
			ID:          "FA6397DA-940A-4310-8A39-E79106BDD4B3",
			Name:        "StepD",
			Status:      "",
			Conclusion:  "",
			StartedAt:   nil,
			CompletedAt: nil,
			Log:         nil,
			ChangeID:    2,
			Number:      4,
		},
	}
}

func mockCheckSteps() []*pbtypes.CheckStep {
	pbTimeAStarted, _ := ptypes.TimestampProto(timeAStarted)
	pbTimeACompleted, _ := ptypes.TimestampProto(timeACompleted)

	pbTimeBStarted, _ := ptypes.TimestampProto(timeBStarted)
	pbTimeBCompleted, _ := ptypes.TimestampProto(timeBCompleted)

	pbTimeCStarted, _ := ptypes.TimestampProto(timeCStarted)

	checkStepLogA := pbtypes.CheckStepLog{
		Id:        1,
		Url:       "",
		LineCount: 1,
	}

	checkStepLogB := pbtypes.CheckStepLog{
		Id:        2,
		Url:       "",
		LineCount: 1,
	}

	return []*pbtypes.CheckStep{
		{
			Id:          "85CF761C-A106-41A0-A5E2-F45F57ACA3DF",
			Name:        "StepA",
			Status:      "completed",
			Conclusion:  "success",
			StartedAt:   pbTimeAStarted,
			CompletedAt: pbTimeACompleted,
			Log:         &checkStepLogA,
			ChangeId:    0,
			Number:      1,
		},
		{
			Id:          "6FC0792B-8713-4F3F-8FFD-7A1946577871",
			Name:        "StepB",
			Status:      "completed",
			Conclusion:  "failure",
			StartedAt:   pbTimeBStarted,
			CompletedAt: pbTimeBCompleted,
			Log:         &checkStepLogB,
			ChangeId:    1,
			Number:      2,
		},
		{
			Id:          "11A0E8E3-E674-4A3C-90AA-D8251CB417CA",
			Name:        "StepC",
			Status:      "in_progress",
			Conclusion:  "",
			StartedAt:   pbTimeCStarted,
			CompletedAt: nil,
			Log:         nil,
			ChangeId:    1,
			Number:      3,
		},
		{
			Id:          "FA6397DA-940A-4310-8A39-E79106BDD4B3",
			Name:        "StepD",
			Status:      "queued",
			Conclusion:  "",
			StartedAt:   nil,
			CompletedAt: nil,
			Log:         nil,
			ChangeId:    2,
			Number:      4,
		},
	}
}

func mockActionsJobSteps() []*azp.ChangeIDResponseJobSteps {
	return []*azp.ChangeIDResponseJobSteps{
		{
			ID:       "f2216faf-e2f4-482a-8a5c-eb14e4f4c4b3",
			ChangeID: 0,
			Steps:    mockActionsSteps(),
		},
		{
			ID:       "923b64a7-7f5d-4078-854c-2f818e35600e",
			ChangeID: 0,
			Steps:    mockActionsSteps(),
		},
	}
}

func mockCheckJobSteps() []*JobSteps {
	return []*JobSteps{
		{
			JobId: "f2216faf-e2f4-482a-8a5c-eb14e4f4c4b3",
			Steps: mockCheckSteps(),
		},
		{
			JobId: "923b64a7-7f5d-4078-854c-2f818e35600e",
			Steps: mockCheckSteps(),
		},
	}
}
