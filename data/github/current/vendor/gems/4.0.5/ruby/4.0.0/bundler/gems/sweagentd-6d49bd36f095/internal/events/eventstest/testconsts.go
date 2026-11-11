package eventstest

import (
	"encoding/base64"
	"fmt"
	"hash/maphash"
	"math"
)

const InstallationID int64 = 22

const (
	RepoName  string = "repo"
	RepoOwner string = "owner"
)

const (
	GitHubAppLogin string = "copilot-swe-agent"
	GitHubBotLogin string = "Copilot"
)

const (
	IssueNumber        = 1
	IssueTitle  string = "issue title"
	IssueBody   string = "issue body"

	IssueCommentBody string = "issue comment body"
)

const (
	PullRequestNumber        = 1
	PullRequestTitle  string = "pr title"
	PullRequestBody   string = "pr body"

	PullRequestReviewBody        string = "pr review body"
	PullRequestReviewCommentBody string = "pr review comment body"
)

const (
	ActorLoginBot    string = "actor-bot"
	ActorLoginAdmin  string = "actor-admin"
	ActorLoginWriter string = "actor-write"
	ActorLoginReader string = "actor-read"
	ActorLoginNone   string = "actor-none"
)

const (
	NameForIDsIssue                    string = "issue"
	NameForIDsPullRequest              string = "pr"
	NameForIDsIssueComment             string = "issue_comment"
	NameForIDsPullRequestReview        string = "pr_review"
	NameForIDsPullRequestReviewComment string = "pr_review_comment"
	NameForIDsWorkflowRun              string = "workflow_run"
	NameForIDsWorkflowJob              string = "workflow_job"
)

var seed = maphash.MakeSeed()

type repository struct {
	ID          int64
	NodeID      string
	OwnerID     int64
	OwnerNodeID string
}

func (r repository) GetRepositoryID() int64 {
	return r.ID
}

func (r repository) GetOwnerID() int64 {
	return r.OwnerID
}

func Repository() repository {
	rID, rNID := IDsFromString(RepoName)
	oID, oNID := IDsFromString(RepoOwner)
	return repository{
		ID:          rID,
		NodeID:      rNID,
		OwnerID:     oID,
		OwnerNodeID: oNID,
	}
}

// IDsFromString returns a deterministic ID and NodeID from a string.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID.
func IDsFromString(str string) (int64, string) {
	nid := base64.StdEncoding.EncodeToString([]byte(str))
	// limit the length of the node id to 40 characters
	nid = nid[:int(math.Min(40, float64(len(nid))))]
	id := int64(maphash.String(seed, str)) & 0x7FFFFFFFFFFFFFFF
	return id, nid
}

// IDsFromStringAndUInt32 returns a deterministic ID and NodeID from a string and uint32.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID. It calls [IDsFromString] with the result
// of [NameForIDsFromStringAndUInt32].
func IDsFromStringAndUInt32(base string, n uint32) (int64, string) {
	return IDsFromString(NameForIDsFromStringAndUInt32(base, n))
}

// IDsFromStringAndInt returns a deterministic ID and NodeID from a string and int.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID. It calls [IDsFromString] with the result
// of [NameForIDsFromStringAndInt].
func IDsFromStringAndInt(base string, n int) (int64, string) {
	return IDsFromString(NameForIDsFromStringAndInt(base, n))
}

// IDsFromStrings returns a deterministic ID and NodeID from a string and a list of strings.
// This is useful for ensuring the IDs represent the same entity across different
// types and test runs resolve to the same ID. It calls [IDsFromString] with the result
// of [NameForIDsFromStrings].
func IDsFromStrings(base string, other ...string) (int64, string) {
	return IDsFromString(NameForIDsFromStrings(base, other...))
}

// NameForIDsFromStringAndUInt32 returns a deterministic string from a string and uint32.
// The result is a string that is the concatenation of the base string and the uint32.
func NameForIDsFromStringAndUInt32(base string, n uint32) string {
	return fmt.Sprintf("%s%d", base, n)
}

// NameForIDsFromStringAndInt returns a deterministic string from a string and int.
// The result is a string that is the concatenation of the base string and the int.
func NameForIDsFromStringAndInt(base string, n int) string {
	return fmt.Sprintf("%s%d", base, n)
}

// NameForIDsFromStrings returns a deterministic string from a string and a list of strings.
// The result is a string that is the concatenation of the base string and the other strings.
func NameForIDsFromStrings(base string, other ...string) string {
	name := base
	for _, str := range other {
		name += str
	}
	return name
}
