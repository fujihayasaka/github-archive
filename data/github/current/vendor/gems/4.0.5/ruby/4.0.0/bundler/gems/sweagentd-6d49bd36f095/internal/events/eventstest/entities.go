package eventstest

import (
	"fmt"

	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func entityIDsFromString(str string) (uint32, int64, string) {
	id, nid := IDsFromString(str)
	smID := uint32(id) & 0xFFFFFFFF
	return smID, id, nid
}

// EntitiesUser returns a new entities.User with the given login.
// The IDs are derived from the login and will be consistent across calls
// and other types representing the same user.
func EntitiesUser(login string) *entities.User {
	id, _, globalID := entityIDsFromString(login)
	user := &entities.User{
		Id:            id,
		Login:         login,
		GlobalRelayId: globalID,
		NextGlobalId:  globalID,
	}
	if login == GitHubBotLogin || login == ActorLoginBot {
		user.Type = entities.User_BOT
	} else {
		user.Type = entities.User_USER
	}
	return user
}

// EntitiesUserCopilot is a convenience function that returns a [entities.User] for Copilot.
func EntitiesUserCopilot() *entities.User {
	return EntitiesUser(GitHubBotLogin)
}

// EntitiesUserAdmin is a convenience function that returns a [entities.User] with admin permissions.
func EntitiesUserAdmin() *entities.User {
	return EntitiesUser(ActorLoginAdmin)
}

// EntitiesUserWriter is a convenience function that returns a [entities.User] with write permissions.
func EntitiesUserWriter() *entities.User {
	return EntitiesUser(ActorLoginWriter)
}

// EntitiesUserReader is a convenience function that returns a [entities.User] with read permissions.
func EntitiesUserReader() *entities.User {
	return EntitiesUser(ActorLoginReader)
}

// EntitiesUserNone is a convenience function that returns a [entities.User] with no permissions.
func EntitiesUserNone() *entities.User {
	return EntitiesUser(ActorLoginNone)
}

// EntitiesRepository returns a [entities.Repository] that can be used across tests.
// The IDs are derived from the repo name and owner, and will be consistent across
// calls and other types representing the same repo.
func EntitiesRepository() *entities.Repository {
	id, _, globalID := entityIDsFromString(RepoName)
	oid, _, _ := entityIDsFromString(RepoOwner)
	return &entities.Repository{
		Id:            id,
		GlobalRelayId: globalID,
		NextGlobalId:  globalID,
		OwnerId:       wrapperspb.UInt32(oid),
		Visibility:    entities.Repository_PRIVATE,
	}
}

// EntitiesPublicRepository returns a [entities.Repository] with public visibility
// that can be used across tests.
func EntitiesPublicRepository() *entities.Repository {
	repo := EntitiesRepository()
	repo.Visibility = entities.Repository_PUBLIC
	return repo
}

// EntitiesIssue returns a [entities.Issue] using [IssueNumber] for the number.
func EntitiesIssue() *entities.Issue {
	return EntitiesIssueWithNumber(IssueNumber)
}

// EntitiesIssueWithNumber returns a [entities.Issue] using the given number.
func EntitiesIssueWithNumber(number uint32) *entities.Issue {
	ids := NameForIDsFromStringAndUInt32(NameForIDsIssue, number)
	id, idValue, globalID := entityIDsFromString(ids)
	return &entities.Issue{
		Id:            id,
		IdValue:       idValue,
		Number:        number,
		IssueState:    entities.Issue_OPEN,
		GlobalRelayId: globalID,
	}
}

// EntitiesPullRequest returns a [entities.PullRequest] using [PullRequestNumber] for the number.
func EntitiesPullRequest() *entities.PullRequest {
	return EntitiesPullRequestWithNumber(PullRequestNumber)
}

// EntitiesPullRequestWithNumber returns a [entities.PullRequest] using the given number.
func EntitiesPullRequestWithNumber(number uint32) *entities.PullRequest {
	ids := NameForIDsFromStringAndUInt32(NameForIDsPullRequest, number)
	_, id, globalID := entityIDsFromString(ids)

	head := fmt.Sprintf("copilot/fix-%d", number)
	base := "main"

	return &entities.PullRequest{
		Id:               uint64(id),
		GlobalRelayId:    globalID,
		PullRequestState: entities.PullRequest_OPEN,
		Draft:            false,
		HeadBranch:       []byte(head),
		BaseBranch:       []byte(base),
	}
}

// EntitiesIssueComment returns a [entities.IssueComment] attributed given author.
func EntitiesIssueComment(author string) *entities.IssueComment {
	ids := NameForIDsIssueComment + author
	id, idValue, globalID := entityIDsFromString(ids)
	return &entities.IssueComment{
		Id:            id,
		IdValue:       idValue,
		GlobalRelayId: globalID,
	}
}

// EntitiesPullRequestReview returns a [entities.PullRequestReview] attributed to the given author.
func EntitiesPullRequestReview(pr uint32, author string) *entities.PullRequestReview {
	prs := NameForIDsFromStringAndUInt32(NameForIDsPullRequest, pr)
	_, prID, _ := entityIDsFromString(prs)
	ids := NameForIDsFromStrings(NameForIDsPullRequestReview, author)
	_, id, _ := entityIDsFromString(ids)
	return &entities.PullRequestReview{
		Id:            uint64(id),
		PullRequestId: uint64(prID),
	}
}

func ActionsWorkflowRunExecution() *actionsv0.WorkflowRunExecution {
	return ActionsWorkflowRunExecutionForPR(PullRequestNumber)
}

func ActionsWorkflowRunExecutionForPR(pr int) *actionsv0.WorkflowRunExecution {
	rID, _ := IDsFromString(RepoName)
	oID, _ := IDsFromString(RepoOwner)
	cID, _ := IDsFromString(GitHubBotLogin)
	wrID, _ := IDsFromStringAndInt(NameForIDsWorkflowRun, pr)

	return &actionsv0.WorkflowRunExecution{
		WorkflowRunId:     int64(wrID),
		RepositoryId:      rID,
		RepositoryOwnerId: oID,
		ActorId:           cID,
		WorkflowRunPath:   "dynamic/copilot-swe-agent/copilot",
		Conclusion:        "success",
		Status:            "completed",
	}
}
