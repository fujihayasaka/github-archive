package eventstest

import (
	"fmt"
	"strconv"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/launcher"
)

// Assignment returns an assignment with the default issue and PR numbers.
// Using this function ensure the issue and PR IDs match the issues and PRs used in tests.
func Assignment() *jobs.Assignment {
	return AssignmentWithPR(PullRequestNumber)
}

// AssignmentWithIssueAndPR returns an assignment with the PR number and the default issue number.
// Using this function ensure the issue and PR IDs match the issues and PRs used in tests.
func AssignmentWithPR(pr int) *jobs.Assignment {
	rID, rNID := IDsFromString(RepoName)
	oID, oNID := IDsFromString(RepoOwner)
	prID, _ := IDsFromStringAndInt(NameForIDsPullRequest, pr)
	return &jobs.Assignment{
		ID:                fmt.Sprintf("assignment-%d", pr),
		OwnerID:           oID,
		RepoID:            rID,
		RepoNodeID:        rNID,
		OwnerNodeID:       oNID,
		PullRequestID:     prID,
		PullRequestNumber: pr,
	}
}

// Job returns a job with the default issue and PR numbers.
// Using this function ensure the issue and PR IDs match the issues and PRs used in tests.
func Job(status jobs.JobStatus) *jobs.Job {
	return JobWithPR(PullRequestNumber, status)
}

func JobWithSessionID(status jobs.JobStatus, sessionId string) *jobs.Job {
	job := JobWithPR(PullRequestNumber, status)
	job.SessionID = sessionId
	return job
}

// JobWWithPR returns a job with the PR number and the default issue number.
// Using this function ensure the issue and PR IDs match the issues and PRs used in tests.
func JobWithPR(pr int, status jobs.JobStatus) *jobs.Job {
	user := GGUserWriter()
	wrID, _ := IDsFromStringAndInt(NameForIDsWorkflowRun, pr)
	job := AssignmentWithPR(pr).NewJob(jobs.AgentActionFix, jobs.JobActor{
		ID:         *user.ID,
		Login:      *user.Login,
		TrackingID: "tracking-id",
	}, "main")

	// override the job ID to match the one used in tests
	job.ID = fmt.Sprintf("job-%d-%s", pr, status)
	job.Status = status
	job.ComputeID = strconv.FormatInt(wrID, 10)
	job.Launcher = launcher.TypeActions

	return job
}
