//nolint:gocritic // hugeParam and rangeValCopy: These structs are passed by value intentionally for interface implementations
package github

import (
	"cmp"
	"context"
	"encoding/json"
	"slices"
	"strconv"
	"strings"
	"time"

	v1 "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/shurcooL/githubv4"
	"golang.org/x/sync/errgroup"
)

// Node represents a GitHub GraphQL node with ID and NodeID fields.
type Node interface {
	GetID() int64
	GetNodeID() string
}

// FullDatabaseID represents a `fullDatabaseId` (BigInt) in the GitHub GraphQL API.
// The GitHub GraphQL API returns `fullDatabaseId` as a string, so we use a custom
// type and unmarshaler to convert it to an int64.
type FullDatabaseID int64

// UnmarshalJSON converts a JSON string to a FullDatabaseID.
func (id *FullDatabaseID) UnmarshalJSON(data []byte) error {
	var str string
	err := json.Unmarshal(data, &str)
	if err != nil {
		return err
	}
	if str == "" {
		*id = 0
		return nil
	}
	i, err := strconv.ParseInt(str, 10, 64)
	if err != nil {
		return err
	}
	*id = FullDatabaseID(i)
	return nil
}

//nolint:funcorder // Helper method is placed near callers for readability
func (id FullDatabaseID) int64() int64 {
	return int64(id)
}

// Ptr returns a pointer to the int64 value.
func (id FullDatabaseID) Ptr() *int64 {
	i := id.int64()
	return &i
}

const (
	// GQLActorTypeUser represents a user actor type.
	GQLActorTypeUser = "User"
	// GQLActorTypeBot represents a bot actor type.
	GQLActorTypeBot = "Bot"
)

// GQLActorOrUser represents an interface for actors that can be users or bots.
type GQLActorOrUser interface {
	GetID() int64
	GetNodeID() string
	GetLogin() string
	GetType() string
}

// GQLActor represents a user or bot.
// When githubv4 marshals the query response to a struct, it will actually set
// common fields on both the User and Bot fields.
type GQLActor struct {
	User struct {
		ID     int64  `graphql:"databaseId" json:"id"`
		NodeID string `graphql:"id"         json:"node_id"`
		Name   string `graphql:"name"       json:"name"`
		Login  string `graphql:"login"      json:"login"`
	} `graphql:"... on User"`

	Bot struct {
		ID     int64  `graphql:"databaseId" json:"id"`
		NodeID string `graphql:"id"         json:"node_id"`
		Login  string `graphql:"login"      json:"login"`
	} `graphql:"... on Bot"`

	Type string `graphql:"__typename" json:"type"`
}

// IsUser returns true if the actor is a user.
func (a GQLActor) IsUser() bool {
	return strings.EqualFold(a.Type, GQLActorTypeUser)
}

// IsBot returns true if the actor is a bot.
func (a GQLActor) IsBot() bool {
	return strings.EqualFold(a.Type, GQLActorTypeBot)
}

// GetTrackingID returns the analytics tracking ID for the actor.
func (a GQLActor) GetTrackingID(ghTwirp githubtwirp.ClientInterface) string {
	if a.IsBot() {
		return "bot"
	}
	resp, err := ghTwirp.UserDetailAPI().GetCopilotUser(
		context.Background(),
		&v1.GetCopilotUserRequest{
			Id: uint64(a.GetID()),
		},
	)
	if err != nil {
		// we should probably log this or something but it's fine to just move on down the road
		return ""
	}
	// yay, we did it!
	return resp.UserDetails.AnalyticsTrackingId
}

// GetID returns the database ID of the actor.
func (a GQLActor) GetID() int64 {
	switch {
	case a.IsUser():
		return a.User.ID
	case a.IsBot():
		return a.Bot.ID
	}
	return 0
}

// GetActorID returns the database ID of the actor.
func (a GQLActor) GetActorID() int64 {
	return a.GetID()
}

// GetNodeID returns the GraphQL node ID of the actor.
func (a GQLActor) GetNodeID() string {
	switch {
	case a.IsUser():
		return a.User.NodeID
	case a.IsBot():
		return a.Bot.NodeID
	}
	return ""
}

// GetName returns the name of the actor.
func (a GQLActor) GetName() string {
	switch {
	case a.IsUser():
		return a.User.Name
	case a.IsBot():
		return ""
	}
	return ""
}

// GetLogin returns the login of the actor.
func (a GQLActor) GetLogin() string {
	switch {
	case a.IsUser():
		return a.User.Login
	case a.IsBot():
		return a.Bot.Login
	}
	return ""
}

// GetType returns the type of the actor.
func (a GQLActor) GetType() string {
	return a.Type
}

// MarshalJSON flattens the actor when marshaling to JSON.
func (a GQLActor) MarshalJSON() ([]byte, error) {
	actor := struct {
		ID     int64  `json:"id,omitempty"`
		NodeID string `json:"node_id,omitempty"`
		Name   string `json:"name,omitempty"`
		Login  string `json:"login,omitempty"`
		Type   string `json:"type,omitempty"`
	}{
		ID:     a.GetID(),
		NodeID: a.GetNodeID(),
		Name:   a.GetName(),
		Login:  a.GetLogin(),
		Type:   a.Type,
	}
	return json.Marshal(&actor)
}

func actorSortFunc(a, b GQLActor) int {
	return cmp.Or(
		cmp.Compare(a.GetID(), b.GetID()),
		strings.Compare(a.GetNodeID(), b.GetNodeID()),
	)
}

func actorEqualFunc(a, b GQLActor) bool {
	return a.GetID() == b.GetID() || a.GetNodeID() == b.GetNodeID()
}

// NewGQLActor creates a new GQLActor for testing.
// When githubv4 marshals the query response to a struct, it will actually set
// common fields on both the User and Bot fields. So we need to do the same here.
func NewGQLActor(id int64, nodeID string, login string, userType string, name string) GQLActor {
	actor := new(GQLActor)
	actor.User.Login = login
	actor.Bot.Login = login
	actor.Type = userType

	actor.User.ID = id
	actor.Bot.ID = id

	actor.User.NodeID = nodeID
	actor.Bot.NodeID = nodeID

	if userType == GQLActorTypeUser {
		actor.User.Name = name
	}
	return *actor
}

// GQLUser represents a user.
// https://docs.github.com/graphql/reference/objects#user
type GQLUser struct {
	ID       int64  `graphql:"databaseId"   json:"id,omitempty"`
	NodeID   string `graphql:"id"           json:"node_id,omitempty"`
	Login    string `json:"login,omitempty"`
	Name     string `json:"name,omitempty"`
	IsViewer bool   `json:"is_viewer"`
}

// GetID returns the database ID of the user.
func (u *GQLUser) GetID() int64 {
	return u.ID
}

// GetActorID returns the database ID of the user.
func (u *GQLUser) GetActorID() int64 {
	return u.GetID()
}

// GetNodeID returns the GraphQL node ID of the user.
func (u *GQLUser) GetNodeID() string {
	return u.NodeID
}

// GetLogin returns the login of the user.
func (u *GQLUser) GetLogin() string {
	return u.Login
}

// GetName returns the name of the user.
func (u *GQLUser) GetName() string {
	return u.Name
}

// GetType returns the type of the user.
func (u *GQLUser) GetType() string {
	return "User"
}

// ToActor converts a GQLUser to a GQLActor.
// When githubv4 marshals the query response to a struct, it will actually set
// common fields on both the User and Bot fields. So we need to do the same here.
func (u *GQLUser) ToActor() GQLActor {
	actor := new(GQLActor)
	actor.User.Login = u.Login
	actor.Bot.Login = u.Login
	actor.Type = GQLActorTypeUser

	actor.User.ID = u.ID
	actor.Bot.ID = u.ID

	actor.User.NodeID = u.NodeID
	actor.Bot.NodeID = u.NodeID

	actor.User.Name = u.Name
	return *actor
}

// GQLReactionContent represents the types of emoji reactions.
type GQLReactionContent string

const (
	// GQLReactionContentConfused represents the :confused: emoji.
	GQLReactionContentConfused GQLReactionContent = "CONFUSED"
	// GQLReactionContentEyes represents the :eyes: emoji.
	GQLReactionContentEyes GQLReactionContent = "EYES"
	// GQLReactionContentHeart represents the :heart: emoji.
	GQLReactionContentHeart GQLReactionContent = "HEART"
	// GQLReactionContentHooray represents the :hooray: emoji.
	GQLReactionContentHooray GQLReactionContent = "HOORAY"
	// GQLReactionContentLaugh represents the :laugh: emoji.
	GQLReactionContentLaugh GQLReactionContent = "LAUGH"
	// GQLReactionContentRocket represents the :rocket: emoji.
	GQLReactionContentRocket GQLReactionContent = "ROCKET"
	// GQLReactionContentThumbsDown represents the :-1: emoji.
	GQLReactionContentThumbsDown GQLReactionContent = "THUMBS_DOWN"
	// GQLReactionContentThumbsUp represents the :+1: emoji.
	GQLReactionContentThumbsUp GQLReactionContent = "THUMBS_UP"
)

// GQLReaction represents an emoji reaction to a particular piece of content.
// https://docs.github.com/graphql/reference/objects#reaction
type GQLReaction struct {
	ID     int64  `graphql:"databaseId" json:"id"`
	NodeID string `graphql:"id"         json:"node_id"`
	// Identifies the emoji reaction.
	// https://docs.github.com/graphql/reference/enums#reactioncontent
	Content   GQLReactionContent `json:"content"`
	CreatedAt time.Time          `json:"created_at"`
	// Identifies the user who created this reaction.
	User GQLUser `json:"user"`
}

// GQLReactions represents a list of emoji reactions to a particular piece of content
type GQLReactions struct {
	GQLConnection[GQLReaction]

	ViewerHasReacted bool `json:"viewer_has_reacted"`
}

// ByAgenticApp returns a list of reactions by the Copilot bot with the given content.
// If content is nil, it will return all reactions by the Copilot bot.
func (r *GQLReactions) ByAgenticApp(content *GQLReactionContent, isAgentic agenticapp.IsAgenticFunc) []GQLReaction {
	reactions := []GQLReaction{}
	for _, reaction := range r.Nodes {
		_, isAgenticUser := isAgentic(&reaction.User)
		if isAgenticUser && (content == nil || reaction.Content == *content) {
			reactions = append(reactions, reaction)
		}
	}
	return reactions
}

// GQLReactable represents a subject that can be reacted on.
// https://docs.github.com/graphql/reference/interfaces#reactable
type GQLReactable struct {
	Reactions GQLReactions `graphql:"reactions(last: $maxReactions)" json:"reactions"`

	ViewerCanReact bool `json:"viewer_can_react"`
}

// Reactable represents a subject that can be reacted on.
type Reactable interface {
	GetReactions() GQLReactions
	AddReaction(ctx context.Context, gh ClientInterface, content GQLReactionContent) error
	RemoveReaction(ctx context.Context, gh ClientInterface, content GQLReactionContent, isAgentic agenticapp.IsAgenticFunc) error
}

// GetReactions returns the reactions for the reactable.
func (r GQLReactable) GetReactions() GQLReactions {
	return r.Reactions
}

// GQLReportedContentClassifier represents the classifier for reported content.
type GQLReportedContentClassifier string

const (
	// GQLReportedContentClassifierAbuse represents an abusive or harassing piece of content.
	GQLReportedContentClassifierAbuse GQLReportedContentClassifier = "ABUSE"
	// GQLReportedContentClassifierDuplicate represents a duplicated piece of content.
	GQLReportedContentClassifierDuplicate GQLReportedContentClassifier = "DUPLICATE"
	// GQLReportedContentClassifierOffTopic represents an irrelevant piece of content.
	GQLReportedContentClassifierOffTopic GQLReportedContentClassifier = "OFF_TOPIC"
	// GQLReportedContentClassifierOutdated represents an outdated piece of content.
	GQLReportedContentClassifierOutdated GQLReportedContentClassifier = "OUTDATED"
	// GQLReportedContentClassifierResolved represents content that has been resolved.
	GQLReportedContentClassifierResolved GQLReportedContentClassifier = "RESOLVED"
	// GQLReportedContentClassifierSpam represents a spammy piece of content.
	GQLReportedContentClassifierSpam GQLReportedContentClassifier = "SPAM"
)

// MinimizedReason returns a string representation of the reason for minimizing content.
// This is used to convert the GQLReportedContentClassifier used by MinimizeComment
// to the values returned by the GitHub API in the `minimized_reason` field of
// GQLMinimizable objects.
func (classifier GQLReportedContentClassifier) MinimizedReason() string {
	switch classifier {
	case GQLReportedContentClassifierAbuse:
		return "abuse"
	case GQLReportedContentClassifierDuplicate:
		return "duplicate"
	case GQLReportedContentClassifierOffTopic:
		return "off-topic"
	case GQLReportedContentClassifierOutdated:
		return "outdated"
	case GQLReportedContentClassifierResolved:
		return "resolved"
	case GQLReportedContentClassifierSpam:
		return "spam"
	default:
		return "unknown"
	}
}

// Minimizable represents entities that can be minimized.
type Minimizable interface {
	GetIsMinimized() bool
	GetMinimizedReason() string
}

// GQLMinimizable represents entities that can be minimized.
// https://docs.github.com/graphql/reference/interfaces#minimizable
type GQLMinimizable struct {
	// Returns whether or not a comment has been minimized.
	IsMinimized bool `json:"is_minimized"`
	// Returns why the comment was minimized. One of abuse, off-topic, outdated, resolved, duplicate and spam.
	// Note that the case and formatting of these values differs from the inputs to the MinimizeComment mutation.
	MinimizedReason string `json:"minimized_reason,omitempty"`
}

// GetIsMinimized returns whether the comment is minimized.
func (m GQLMinimizable) GetIsMinimized() bool {
	return m.IsMinimized
}

// GetMinimizedReason returns the reason the comment was minimized.
func (m GQLMinimizable) GetMinimizedReason() string {
	return m.MinimizedReason
}

// GQLLabel represents a label for categorizing Issues, Pull Requests, Milestones,
// or Discussions with a given Repository.
// https://docs.github.com/graphql/reference/objects#label
type GQLLabel struct {
	NodeID      string `graphql:"id"       json:"node_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// GetName returns the name of the label.
func (l GQLLabel) GetName() string {
	return l.Name
}

// Labelable represents an object that can have labels.
type Labelable interface {
	GetLabels() GQLConnection[GQLLabel]
}

// GQLLabelable represents an object that can be labeled.
// https://docs.github.com/graphql/reference/interfaces#labelable
type GQLLabelable struct {
	Labels GQLConnection[GQLLabel] `graphql:"labels(first: $maxLabels, orderBy: {field: NAME, direction: ASC})" json:"labels"`

	ViewerCanLabel bool `json:"viewer_can_label"`
}

// GetLabels returns the labels for the labelable.
func (l GQLLabelable) GetLabels() GQLConnection[GQLLabel] {
	return l.Labels
}

// GQLConnection represents a connection to a list of items.
type GQLConnection[E any] struct {
	TotalCount int `json:"total_count,omitempty"`
	Nodes      []E `json:"nodes,omitempty"`
}

// Len returns the number of nodes in the connection.
func (c GQLConnection[E]) Len() int {
	return len(c.Nodes)
}

// MarshalJSON flattens the connection when marshaling to JSON.
func (c GQLConnection[E]) MarshalJSON() ([]byte, error) {
	return json.Marshal(&c.Nodes)
}

// GQLCommentAuthorAssociation represents the association of an author to a repository.
type GQLCommentAuthorAssociation string

const (
	// GQLCommentAuthorAssociationCollaborator indicates the author has been invited to collaborate on the repository.
	GQLCommentAuthorAssociationCollaborator GQLCommentAuthorAssociation = "COLLABORATOR"
	// GQLCommentAuthorAssociationContributor indicates the author has previously committed to the repository.
	GQLCommentAuthorAssociationContributor GQLCommentAuthorAssociation = "CONTRIBUTOR"
	// GQLCommentAuthorAssociationFirstTimer indicates the author has not previously committed to GitHub.
	GQLCommentAuthorAssociationFirstTimer GQLCommentAuthorAssociation = "FIRST_TIMER"
	// GQLCommentAuthorAssociationFirstTimeContributor indicates the author has not previously committed to the repository.
	GQLCommentAuthorAssociationFirstTimeContributor GQLCommentAuthorAssociation = "FIRST_TIME_CONTRIBUTOR"
	// GQLCommentAuthorAssociationMannequin indicates the author is a placeholder for an unclaimed user.
	GQLCommentAuthorAssociationMannequin GQLCommentAuthorAssociation = "MANNEQUIN"
	// GQLCommentAuthorAssociationMember indicates the author is a member of the organization that owns the repository.
	GQLCommentAuthorAssociationMember GQLCommentAuthorAssociation = "MEMBER"
	// GQLCommentAuthorAssociationNone indicates the author has no association with the repository.
	GQLCommentAuthorAssociationNone GQLCommentAuthorAssociation = "NONE"
	// GQLCommentAuthorAssociationOwner indicates the author is the owner of the repository.
	GQLCommentAuthorAssociationOwner GQLCommentAuthorAssociation = "OWNER"
)

// Comment represents an interface for comments.
type Comment interface {
	Node
	Reactable
	GetAuthor() GQLActor
	GetBody() string
}

// GqlCommentCore contains the fields shared by all comment types.
// Extracted to allow reuse between the standard query types (which include
// reactions) and the fallback query types (which omit reactions).
type GqlCommentCore struct {
	ID                FullDatabaseID              `graphql:"fullDatabaseId"  json:"id"`
	NodeID            string                      `graphql:"id"              json:"node_id"`
	Author            GQLActor                    `json:"author"`
	AuthorAssociation GQLCommentAuthorAssociation `json:"author_association"`
	Body              string                      `json:"body"`
	CreatedAt         time.Time                   `json:"created_at"`
	PublishedAt       time.Time                   `json:"published_at"`
	UpdatedAt         time.Time                   `json:"updated_at"`
	ViewerDidAuthor   bool                        `json:"viewer_did_author"`
}

// GQLComment represents a comment.
// https://docs.github.com/graphql/reference/interfaces#comment
type GQLComment struct {
	GQLReactable
	GqlCommentCore
}

// GetID returns the database ID of the comment.
func (c GQLComment) GetID() int64 {
	return c.ID.int64()
}

// GetNodeID returns the GraphQL node ID of the comment.
func (c GQLComment) GetNodeID() string {
	return c.NodeID
}

// GetBody returns the body of the comment.
func (c GQLComment) GetBody() string {
	return c.Body
}

// GetAuthor returns the author of the comment.
func (c GQLComment) GetAuthor() GQLActor {
	return c.Author
}

// AddReaction adds a reaction to the comment.
func (c GQLComment) AddReaction(ctx context.Context, gh ClientInterface, content GQLReactionContent) error {
	// adding a reaction that already exists is a no-op
	return gh.AddReaction(ctx, c.NodeID, content)
}

// RemoveReaction removes a reaction from the comment.
func (c GQLComment) RemoveReaction(ctx context.Context, gh ClientInterface, content GQLReactionContent, isAgentic agenticapp.IsAgenticFunc) error {
	// removing a reaction that doesn't exist will return an error
	index := -1
	for i, reaction := range c.Reactions.Nodes {
		_, isAgenticUser := isAgentic(&reaction.User)
		if isAgenticUser && reaction.Content == content {
			index = i
			break
		}
	}
	if index == -1 {
		return nil
	}

	// remove the reaction from the nodes
	c.Reactions.Nodes = slices.Delete(c.Reactions.Nodes, index, index+1)

	return gh.RemoveReaction(ctx, c.NodeID, content)
}

// Assignable represents an object that can be assigned to.
type Assignable interface {
	GetAssignees() GQLConnection[GQLUser]
	GetAssignedActors() GQLConnection[GQLActor]
}

// GQLAssignable represents an object that can be assigned to.
// https://docs.github.com/graphql/reference/interfaces#assignable
type GQLAssignable struct {
	Assignees      GQLConnection[GQLUser]  `graphql:"assignees(first: $maxAssignees)"      json:"assignees"`
	AssignedActors GQLConnection[GQLActor] `graphql:"assignedActors(first: $maxAssignees)" json:"assigned_actors"`
}

// GetAssignees returns the assignees for the assignable.
func (a GQLAssignable) GetAssignees() GQLConnection[GQLUser] {
	return a.Assignees
}

// GetAssignedActors returns the assigned actors for the assignable.
func (a GQLAssignable) GetAssignedActors() GQLConnection[GQLActor] {
	return a.AssignedActors
}

// IsAgenticAppAssigned returns true if an agentic app is assigned.
func (a GQLAssignable) IsAgenticAppAssigned(isAgentic agenticapp.IsAgenticFunc) bool {
	// First check AssignedActors which supports both users and bots
	for _, actor := range a.AssignedActors.Nodes {
		if _, isCopilot := isAgentic(actor); isCopilot {
			return true
		}
	}

	// Fallback to Assignees for backward compatibility
	for _, assignee := range a.Assignees.Nodes {
		if _, isCopilot := isAgentic(&assignee); isCopilot {
			return true
		}
	}

	return false
}

// Closeable represents an object that can be closed.
type Closeable interface {
	IsClosed() bool
	GetClosedAt() *time.Time
}

// GQLCloseable represents an object that can be closed.
// https://docs.github.com/graphql/reference/interfaces#closeable
type GQLCloseable struct {
	Closed   bool       `json:"closed"`
	ClosedAt *time.Time `json:"closed_at,omitempty"`
}

// IsClosed returns whether the object is closed.
func (c GQLCloseable) IsClosed() bool {
	return c.Closed
}

// GetClosedAt returns the time when the object was closed.
func (c GQLCloseable) GetClosedAt() *time.Time {
	return c.ClosedAt
}

// GQLIssueState represents the state of an issue.
type GQLIssueState string

const (
	// GQLIssueStateClosed indicates an issue that has been closed.
	GQLIssueStateClosed GQLIssueState = "CLOSED"
	// GQLIssueStateOpen indicates an issue that is still open.
	GQLIssueStateOpen GQLIssueState = "OPEN"
)

// GQLGitObject represents a Git object.
// https://docs.github.com/graphql/reference/interfaces#gitobject
type GQLGitObject struct {
	AbbreviatedOID string `graphql:"abbreviatedOid" json:"abbreviated_oid"`
	OID            string `graphql:"oid"            json:"oid"`
}

// Issue represents an interface for issues.
type Issue interface {
	Comment
	Reactable
	Assignable
	Closeable
	Labelable
	GetNumber() int
	GetComments() GQLConnection[GQLIssueComment]
	IsPullRequest() bool
	AssignToCopilot(ctx context.Context, gh ClientInterface) error
}

// GQLIssue represents an issue.
// https://docs.github.com/graphql/reference/objects#issue
type GQLIssue struct {
	GQLComment
	GQLAssignable
	GQLCloseable
	GQLLabelable

	Title        string                         `json:"title"`
	Number       int                            `json:"number"`
	State        GQLIssueState                  `json:"state"`
	Participants GQLConnection[GQLUser]         `graphql:"participants(first: $maxParticipants)" json:"participants"`
	Comments     GQLConnection[GQLIssueComment] `graphql:"comments(last: $maxComments)"          json:"comments"`
	// Used to make sure we haven't hit a race condition with the issue body
	LastEditedAt *time.Time `json:"last_edited_at,omitempty"`
}

// GetNumber returns the number of the issue.
func (i GQLIssue) GetNumber() int {
	return i.Number
}

// GetComments returns the comments on the issue.
func (i GQLIssue) GetComments() GQLConnection[GQLIssueComment] {
	return i.Comments
}

// IsPullRequest returns false for issues.
func (i GQLIssue) IsPullRequest() bool {
	return false
}

// GetParticipants returns all participants on the issue.
func (i GQLIssue) GetParticipants() []GQLActor {
	participants := []GQLActor{}
	participants = append(participants, i.Author)
	for _, p := range i.Participants.Nodes {
		participants = append(participants, p.ToActor())
	}
	for _, c := range i.Comments.Nodes {
		participants = append(participants, c.Author)
	}
	return participants
}

// AssignToCopilot assigns the Copilot bot to the issue.
func (i GQLIssue) AssignToCopilot(ctx context.Context, gh ClientInterface) error {
	issueID := i.GetNodeID()

	copilot, err := gh.GetCopilotBotUser(ctx)
	if err != nil {
		return err
	}

	assignees := []string{}
	// Prefer AssignedActors which supports both users and bots
	if len(i.AssignedActors.Nodes) > 0 {
		for _, actor := range i.AssignedActors.Nodes {
			assignees = append(assignees, actor.GetNodeID())
		}
	} else {
		// Fallback to Assignees for backward compatibility
		for _, assignee := range i.Assignees.Nodes {
			assignees = append(assignees, assignee.GetNodeID())
		}
	}
	assignees = append(assignees, copilot.GetNodeID())

	// This replaces the list of assignees vs appends
	return gh.ReplaceActorsForAssignable(ctx, issueID, assignees)
}

// GQLIssueComment represents a comment on an issue.
// https://docs.github.com/graphql/reference/objects#issuecomment
//
//nolint:recvcheck // Mixed receivers are required for interface implementations
type GQLIssueComment struct {
	GQLComment
	GQLMinimizable

	URL string `json:"url"`
}

// Minimize minimizes the comment with the given reason.
func (c *GQLIssueComment) Minimize(ctx context.Context, gh ClientInterface, reason GQLReportedContentClassifier) error {
	if c.IsMinimized {
		return nil
	}
	err := gh.MinimizeComment(ctx, c.NodeID, reason)
	if err != nil {
		return err
	}
	c.IsMinimized = true
	c.MinimizedReason = reason.MinimizedReason()
	return nil
}

// Unminimize unminimizes the comment.
func (c *GQLIssueComment) Unminimize(ctx context.Context, gh ClientInterface) error {
	if !c.IsMinimized {
		return nil
	}
	err := gh.UnminimizeComment(ctx, c.NodeID)
	if err != nil {
		return err
	}
	c.IsMinimized = false
	c.MinimizedReason = ""
	return nil
}

// GetURL returns the URL of the comment.
func (c *GQLIssueComment) GetURL() string {
	return c.URL
}

// GQLRef represents a Git reference.
// https://docs.github.com/graphql/reference/objects#ref
type GQLRef struct {
	NodeID string       `graphql:"id"  json:"node_id"`
	Name   string       `json:"name"`
	Prefix string       `json:"prefix"`
	Target GQLGitObject `json:"target"`
}

// GQLPullRequest represents a pull request.
// https://docs.github.com/graphql/reference/objects#pullrequest
type GQLPullRequest struct {
	GQLComment
	GQLAssignable
	GQLCloseable
	GQLLabelable

	Title              string                                    `json:"title"`
	Number             int                                       `json:"number"`
	IsDraft            bool                                      `json:"is_draft"`
	BaseRef            GQLRef                                    `json:"base_ref"`
	HeadRef            GQLRef                                    `json:"head_ref"`
	Participants       GQLConnection[GQLUser]                    `graphql:"participants(first: $maxParticipants)" json:"participants"`
	Comments           GQLConnection[GQLIssueComment]            `graphql:"comments(last: $maxComments)"          json:"comments"`
	Reviews            GQLConnection[GQLPullRequestReview]       `graphql:"reviews(last: $maxComments)"           json:"reviews"`
	ReviewThreads      GQLConnection[GQLPullRequestReviewThread] `graphql:"reviewThreads(last: $maxComments)"     json:"review_threads"`
	TotalCommentsCount int                                       `json:"total_comments_count"`
	IsCrossRepository  bool                                      `json:"is_cross_repository"`
	Commits            struct {
		TotalCount int `json:"total_count"`
	} `json:"commits"`
}

// GetNumber returns the number of the pull request.
func (pr *GQLPullRequest) GetNumber() int {
	return pr.Number
}

// GetComments returns the comments on the pull request.
func (pr *GQLPullRequest) GetComments() GQLConnection[GQLIssueComment] {
	return pr.Comments
}

// IsPullRequest returns true for pull requests.
func (pr *GQLPullRequest) IsPullRequest() bool {
	return true
}

// ReviewByID returns the review with the given ID.
func (pr *GQLPullRequest) ReviewByID(id int64) *GQLPullRequestReview {
	for _, review := range pr.Reviews.Nodes {
		if review.GetID() == id {
			return &review
		}
	}
	return nil
}

// CommentByID returns the comment with the given ID.
func (pr *GQLPullRequest) CommentByID(id int64) *GQLIssueComment {
	for _, comment := range pr.Comments.Nodes {
		if comment.GetID() == id {
			return &comment
		}
	}
	return nil
}

// ReviewCommentByID returns the review comment with the given ID.
func (pr *GQLPullRequest) ReviewCommentByID(id int64) *GQLPullRequestReviewComment {
	for _, review := range pr.Reviews.Nodes {
		for _, comment := range review.Comments.Nodes {
			if comment.GetID() == id {
				return &comment
			}
		}
	}
	return nil
}

// GetParticipants returns all participants on the pull request.
func (pr *GQLPullRequest) GetParticipants() []GQLActor {
	participants := []GQLActor{}
	participants = append(participants, pr.Author)
	for _, p := range pr.Participants.Nodes {
		participants = append(participants, p.ToActor())
	}
	for _, c := range pr.Comments.Nodes {
		participants = append(participants, c.Author)
	}
	for _, r := range pr.Reviews.Nodes {
		participants = append(participants, r.Author)
		for _, c := range r.Comments.Nodes {
			participants = append(participants, c.Author)
		}
	}
	return participants
}

// GetReviewThreadResolvedMap returns a map of comment IDs to their thread's resolved status.
// This is more efficient than repeatedly calling IsReviewCommentThreadResolved for each comment,
// as it builds the map once in O(n*m) time and then lookups are O(1).
func (pr *GQLPullRequest) GetReviewThreadResolvedMap() map[int64]bool {
	resolvedMap := make(map[int64]bool, len(pr.ReviewThreads.Nodes))
	for _, thread := range pr.ReviewThreads.Nodes {
		for _, comment := range thread.Comments.Nodes {
			resolvedMap[comment.GetID()] = thread.IsResolved
		}
	}
	return resolvedMap
}

// AssignToCopilot assigns the Copilot bot to the pull request.
func (pr *GQLPullRequest) AssignToCopilot(ctx context.Context, gh ClientInterface) error {
	prID := pr.GetNodeID()

	copilot, err := gh.GetCopilotBotUser(ctx)
	if err != nil {
		return err
	}

	assignees := []string{}
	// Prefer AssignedActors which supports both users and bots
	if len(pr.AssignedActors.Nodes) > 0 {
		for _, actor := range pr.AssignedActors.Nodes {
			assignees = append(assignees, actor.GetNodeID())
		}
	} else {
		// Fallback to Assignees for backward compatibility
		for _, assignee := range pr.Assignees.Nodes {
			assignees = append(assignees, assignee.GetNodeID())
		}
	}
	assignees = append(assignees, copilot.GetNodeID())

	// This replaces the list of assignees vs appends
	return gh.ReplaceActorsForAssignable(ctx, prID, assignees)
}

// GQLPullRequestReviewState represents the state of a pull request review.
type GQLPullRequestReviewState string

const (
	// GQLPullRequestReviewStateApproved is a review allowing the pull request to merge.
	GQLPullRequestReviewStateApproved GQLPullRequestReviewState = "APPROVED"
	// GQLPullRequestReviewStateChangesRequested is a review blocking the pull request from merging.
	GQLPullRequestReviewStateChangesRequested GQLPullRequestReviewState = "CHANGES_REQUESTED"
	// GQLPullRequestReviewStateCommented is an informational review.
	GQLPullRequestReviewStateCommented GQLPullRequestReviewState = "COMMENTED"
	// GQLPullRequestReviewStateDismissed is a review that has been dismissed.
	GQLPullRequestReviewStateDismissed GQLPullRequestReviewState = "DISMISSED"
	// GQLPullRequestReviewStatePending is a review that has not yet been submitted.
	GQLPullRequestReviewStatePending GQLPullRequestReviewState = "PENDING"
)

// GQLPullRequestReview represents review object for a given pull request.
// https://docs.github.com/graphql/reference/objects#pullrequestreview
type GQLPullRequestReview struct {
	GQLComment
	GQLMinimizable

	// Indicates whether the author of this review has push access to the repository.
	AuthorCanPushToRepository bool                                       `json:"author_can_push_to_repository"`
	Comments                  GQLConnection[GQLPullRequestReviewComment] `graphql:"comments(last: $maxComments)" json:"comments"`
	State                     GQLPullRequestReviewState                  `json:"state"`
	SubmittedAt               time.Time                                  `json:"submitted_at"`
	URL                       string                                     `json:"url"`
}

// Minimize minimizes the review with the given reason.
func (r *GQLPullRequestReview) Minimize(ctx context.Context, gh ClientInterface, reason GQLReportedContentClassifier) error {
	if r.IsMinimized {
		return nil
	}
	err := gh.MinimizeComment(ctx, r.NodeID, reason)
	if err != nil {
		return err
	}
	r.IsMinimized = true
	r.MinimizedReason = reason.MinimizedReason()
	return nil
}

// Unminimize unminimizes the review.
func (r *GQLPullRequestReview) Unminimize(ctx context.Context, gh ClientInterface) error {
	if !r.IsMinimized {
		return nil
	}
	err := gh.UnminimizeComment(ctx, r.NodeID)
	if err != nil {
		return err
	}
	r.IsMinimized = false
	r.MinimizedReason = ""
	return nil
}

// CommentByID returns the comment with the given ID.
func (r *GQLPullRequestReview) CommentByID(id int64) *GQLPullRequestReviewComment {
	for _, comment := range r.Comments.Nodes {
		if comment.GetID() == id {
			return &comment
		}
	}
	return nil
}

// GetURL returns the URL of the review.
func (r *GQLPullRequestReview) GetURL() string {
	return r.URL
}

// IsReviewCommentReply returns true if the review is a reply to another pull request
// review comment. Inline comments to "threads" on pull request review actually
// create a new pull request review. The new review will always have a state of
// "COMMENTED" and a single comment that is a reply to the original review comment.
func (r *GQLPullRequestReview) IsReviewCommentReply() bool {
	// check the total count and the length because comments may have been filtered
	if r.Commented() && r.Comments.TotalCount == 1 && r.Comments.Len() == 1 {
		return r.Comments.Nodes[0].ReplyTo != nil
	}
	return false
}

// IsTopLevelCommentOnly returns true the review doesn't specifically request changes,
// and only includes a top-level comment (has a body) with no inline review comments
// associated with a file or line. This also means the review is not a reply to another
// pull request review comment, and is not a approval or dismissal.
func (r *GQLPullRequestReview) IsTopLevelCommentOnly() bool {
	// check the total count and the length because comments may have been filtered
	return r.Commented() && r.Body != "" && r.Comments.TotalCount == 0 && r.Comments.Len() == 0
}

// Pending returns true if the review is pending.
func (r *GQLPullRequestReview) Pending() bool {
	return r.State == GQLPullRequestReviewStatePending
}

// Approved returns true if the review is approved.
func (r *GQLPullRequestReview) Approved() bool {
	return r.State == GQLPullRequestReviewStateApproved
}

// ChangesRequested returns true if the review requests changes.
func (r *GQLPullRequestReview) ChangesRequested() bool {
	return r.State == GQLPullRequestReviewStateChangesRequested
}

// Commented returns true if the review is a comment.
func (r *GQLPullRequestReview) Commented() bool {
	return r.State == GQLPullRequestReviewStateCommented
}

// Dismissed returns true if the review is dismissed.
func (r *GQLPullRequestReview) Dismissed() bool {
	return r.State == GQLPullRequestReviewStateDismissed
}

// GQLPullRequestReviewCommentState represents the state of a pull request review comment.
type GQLPullRequestReviewCommentState string

const (
	// GQLPullRequestReviewCommentStatePendin is a comment that is part of a pending review.
	GQLPullRequestReviewCommentStatePendin GQLPullRequestReviewCommentState = "PENDING"
	// GQLPullRequestReviewCommentStateSubmitted is a comment that is part of a submitted review.
	GQLPullRequestReviewCommentStateSubmitted GQLPullRequestReviewCommentState = "SUBMITTED"
)

// GQLPullRequestReviewThreadSubjectType represents the subject type of a pull request review thread.
type GQLPullRequestReviewThreadSubjectType string

const (
	// GQLPullRequestReviewThreadSubjectTypeFile is a comment that has been made against the file of a pull request.
	GQLPullRequestReviewThreadSubjectTypeFile GQLPullRequestReviewThreadSubjectType = "FILE"
	// GQLPullRequestReviewThreadSubjectTypeLine is a comment that has been made against the line of a pull request.
	GQLPullRequestReviewThreadSubjectTypeLine GQLPullRequestReviewThreadSubjectType = "LINE"
)

// GQLPullRequestReviewIDs represents the IDs of a pull request review.
type GQLPullRequestReviewIDs struct {
	ID     FullDatabaseID `graphql:"fullDatabaseId" json:"id"`
	NodeID string         `graphql:"id"             json:"node_id"`
}

// GetID returns the database ID of the review.
func (r GQLPullRequestReviewIDs) GetID() int64 {
	return r.ID.int64()
}

// GetNodeID returns the GraphQL node ID of the review.
func (r GQLPullRequestReviewIDs) GetNodeID() string {
	return r.NodeID
}

// GQLReplyTo represents a reply to a pull request review comment.
type GQLReplyTo struct {
	ID                FullDatabaseID          `graphql:"fullDatabaseId"   json:"id"`
	NodeID            string                  `graphql:"id"               json:"node_id"`
	PullRequestReview GQLPullRequestReviewIDs `json:"pull_request_review"`
}

// GetID returns the database ID of the reply.
func (r GQLReplyTo) GetID() int64 {
	return r.ID.int64()
}

// GetNodeID returns the GraphQL node ID of the reply.
func (r GQLReplyTo) GetNodeID() string {
	return r.NodeID
}

// GQLPullRequestReviewThread represents a threaded list of comments on a code review.
// https://docs.github.com/graphql/reference/objects#pullrequestreviewthread
type GQLPullRequestReviewThread struct {
	IsResolved bool                                       `json:"is_resolved"`
	Comments   GQLConnection[GQLPullRequestReviewComment] `graphql:"comments(last: $maxComments)" json:"comments"`
}

// GQLPullRequestReviewComment represents a review comment associated with a given repository pull request.
// https://docs.github.com/graphql/reference/objects#pullrequestreviewcomment
// GqlReviewCommentFields contains the fields specific to review comments,
// shared between standard and fallback query types.
type GqlReviewCommentFields struct {
	Commit            GQLGitObject                          `json:"commit"`
	Path              string                                `json:"path"`
	Line              int                                   `json:"line"`
	StartLine         int                                   `json:"start_line"`
	OriginalLine      int                                   `json:"original_line"`
	OriginalStartLine int                                   `json:"original_start_line"`
	OriginalCommit    GQLGitObject                          `json:"original_commit"`
	State             GQLPullRequestReviewCommentState      `json:"state"`
	SubjectType       GQLPullRequestReviewThreadSubjectType `json:"subject_type"`
	PullRequestReview GQLPullRequestReviewIDs               `json:"pull_request_review"`
	ReplyTo           *GQLReplyTo                           `json:"reply_to,omitempty"`
	URL               string                                `json:"url"`
}

type GQLPullRequestReviewComment struct {
	GQLComment
	GQLMinimizable
	GqlReviewCommentFields
}

// OnLine returns true if the review subject type is "LINE".
func (r *GQLPullRequestReviewComment) OnLine() bool {
	return r.SubjectType == GQLPullRequestReviewThreadSubjectTypeLine
}

// OnFile returns true if the review subject type is "FILE".
func (r *GQLPullRequestReviewComment) OnFile() bool {
	return r.SubjectType == GQLPullRequestReviewThreadSubjectTypeFile
}

// Minimize minimizes the comment with the given reason.
func (r *GQLPullRequestReviewComment) Minimize(ctx context.Context, gh ClientInterface, reason GQLReportedContentClassifier) error {
	if r.IsMinimized {
		return nil
	}
	err := gh.MinimizeComment(ctx, r.NodeID, reason)
	if err != nil {
		return err
	}
	r.IsMinimized = true
	r.MinimizedReason = reason.MinimizedReason()
	return nil
}

// Unminimize unminimizes the comment.
func (r *GQLPullRequestReviewComment) Unminimize(ctx context.Context, gh ClientInterface) error {
	if !r.IsMinimized {
		return nil
	}
	err := gh.UnminimizeComment(ctx, r.NodeID)
	if err != nil {
		return err
	}
	r.IsMinimized = false
	r.MinimizedReason = ""
	return nil
}

// GetURL returns the URL of the comment.
func (r *GQLPullRequestReviewComment) GetURL() string {
	return r.URL
}

// GQLRepositoryPlanFeatures contains information about the availability of features
// and limits for a repository based on its billing plan.
// https://docs.github.com/graphql/reference/objects#repositoryplanfeatures
type GQLRepositoryPlanFeatures struct {
	// Whether reviews can be automatically requested and enforced with a CODEOWNERS file.
	Codeowners bool `json:"codeowners"`
	// Whether pull requests can be created as or converted to draft.
	DraftPullRequests bool `json:"draftPullRequests"`
	// Maximum number of users that can be assigned to an issue or pull request.
	MaximumAssignees int `json:"maximumAssignees"`
	// Maximum number of manually-requested reviews on a pull request.
	MaximumManualReviewRequests int `json:"maximumManualReviewRequests"`
	// Whether teams can be requested to review pull requests.
	TeamReviewRequests bool `json:"teamReviewRequests"`
}

// GQLRepositoryPermission represents the permission level for a repository.
type GQLRepositoryPermission string

const (
	// GQLRepositoryPermissionAdmin can read, clone, and push to this repository.
	// Can also manage issues, pull requests, and repository settings, including adding collaborators.
	GQLRepositoryPermissionAdmin = "ADMIN"
	// GQLRepositoryPermissionMaintain can read, clone, and push to this repository.
	// They can also manage issues, pull requests, and some repository settings.
	GQLRepositoryPermissionMaintain = "MAINTAIN"
	// GQLRepositoryPermissionRead can read and clone this repository.
	// Can also open and comment on issues and pull requests.
	GQLRepositoryPermissionRead = "READ"
	// GQLRepositoryPermissionTriage can read and clone this repository.
	// Can also manage issues and pull requests.
	GQLRepositoryPermissionTriage = "TRIAGE"
	// GQLRepositoryPermissionWrite can read, clone, and push to this repository.
	// Can also manage issues and pull requests.
	GQLRepositoryPermissionWrite = "WRITE"
)

// GQLRepositoryVisibility represents the visibility of a repository.
type GQLRepositoryVisibility string

const (
	// GQLRepositoryVisibilityInternal indicates the repository is visible only to users in the same enterprise.
	GQLRepositoryVisibilityInternal GQLRepositoryVisibility = "INTERNAL"

	// GQLRepositoryVisibilityPrivate indicates the repository is visible only to those with explicit access.
	GQLRepositoryVisibilityPrivate GQLRepositoryVisibility = "PRIVATE"

	// GQLRepositoryVisibilityPublic indicates the repository is visible to everyone.
	GQLRepositoryVisibilityPublic GQLRepositoryVisibility = "PUBLIC"
)

// GQLRepository represents a repository.
// https://docs.github.com/graphql/reference/objects#repository
type GQLRepository struct {
	ID               int64              `graphql:"databaseId"      json:"id"`
	NodeID           string             `graphql:"id"              json:"node_id"`
	Name             string             `json:"name"`
	NameWithOwner    string             `json:"name_with_owner"`
	DefaultBranchRef *GQLRef            `json:"default_branch_ref"`
	HasIssuesEnabled bool               `json:"has_issues_enabled"`
	Owner            GQLRepositoryOwner `json:"owner"`
	// Identifies if the repository is private or internal.
	IsPrivate    bool                      `json:"is_private"`
	Visibility   GQLRepositoryVisibility   `json:"visibility"`
	PlanFeatures GQLRepositoryPlanFeatures `json:"plan_features"`
}

// GetDefaultBranch returns the default branch of the repository.
func (r *GQLRepository) GetDefaultBranch() string {
	if r.DefaultBranchRef != nil {
		return r.DefaultBranchRef.Name
	}
	return ""
}

// GQLRepositoryOwnerType represents an owner of a repository.
type GQLRepositoryOwnerType string

const (
	// GQLRepositoryOwnerTypeUser represents a user owner.
	GQLRepositoryOwnerTypeUser = "User"
	// GQLRepositoryOwnerTypeOrganization represents an organization owner.
	GQLRepositoryOwnerTypeOrganization = "Organization"
)

// GQLRepositoryOwner represents an owner of a repository.
// https://docs.github.com/graphql/reference/interfaces#repositoryowner
// When githubv4 marshals the query response to a struct, it will actually set
// common fields on both the User and Organization fields.
type GQLRepositoryOwner struct {
	User struct {
		ID   int64  `graphql:"databaseId"  json:"id"`
		Name string `json:"name,omitempty"`
	} `graphql:"... on User"`

	Organization struct {
		ID   int64  `graphql:"databaseId"  json:"id"`
		Name string `json:"name,omitempty"`
	} `graphql:"... on Organization"`

	NodeID string `graphql:"id"         json:"node_id"`
	Login  string `graphql:"login"      json:"login"`
	Type   string `graphql:"__typename" json:"type"`
}

// IsUser returns true if the owner is a user.
func (a GQLRepositoryOwner) IsUser() bool {
	return strings.EqualFold(a.Type, GQLRepositoryOwnerTypeUser)
}

// IsOrg returns true if the owner is an organization.
func (a GQLRepositoryOwner) IsOrg() bool {
	return strings.EqualFold(a.Type, GQLRepositoryOwnerTypeOrganization)
}

// GetID returns the database ID of the owner.
func (a GQLRepositoryOwner) GetID() int64 {
	switch {
	case a.IsUser():
		return a.User.ID
	case a.IsOrg():
		return a.Organization.ID
	}
	return 0
}

// GetName returns the name of the owner.
func (a GQLRepositoryOwner) GetName() string {
	switch {
	case a.IsUser():
		return a.User.Name
	case a.IsOrg():
		return a.Organization.Name
	}
	return ""
}

// NewGQLRepositoryOwner creates a new GQLRepositoryOwner for testing.
// When githubv4 marshals the query response to a struct, it will actually set
// common fields on both the User and Organization fields. So we need to do the same here.
func NewGQLRepositoryOwner(id int64, nodeID string, login string, ownerType GQLRepositoryOwnerType, name string) GQLRepositoryOwner {
	owner := new(GQLRepositoryOwner)
	owner.Login = login
	owner.Type = string(ownerType)
	owner.NodeID = nodeID

	owner.User.ID = id
	owner.Organization.ID = id

	owner.User.Name = name
	owner.Organization.Name = name

	return *owner
}

// MarshalJSON flattens the repository owner when marshaling to JSON.
func (a GQLRepositoryOwner) MarshalJSON() ([]byte, error) {
	actor := struct {
		ID     int64  `json:"id,omitempty"`
		NodeID string `json:"node_id,omitempty"`
		Name   string `json:"name,omitempty"`
		Login  string `json:"login,omitempty"`
		Type   string `json:"type,omitempty"`
	}{
		ID:     a.GetID(),
		NodeID: a.NodeID,
		Name:   a.GetName(),
		Login:  a.Login,
		Type:   a.Type,
	}
	return json.Marshal(&actor)
}

// GQLRepositoryContext represents a repository context for GraphQL queries.
type GQLRepositoryContext struct {
	GQLRepository
}

// GQLIssueContext represents an issue context for GraphQL queries.
type GQLIssueContext struct {
	GQLRepository

	Issue GQLIssue `graphql:"issue(number: $number)" json:"issue"`
}

// GQLPullRequestContext represents a pull request context for GraphQL queries.
type GQLPullRequestContext struct {
	GQLRepository

	PullRequest GQLPullRequest `graphql:"pullRequest(number: $number)" json:"pull_request"`
}

type issueContext interface {
	getContextParticipants() []ContextParticipant
	PermissionsFor(actor GQLActor) *RepositoryPermissions
}

// RepositoryContext represents a repository context.
type RepositoryContext struct {
	Repository GQLRepository `json:"repository"`
}

// IssueContext represents an issue context with repository and participant information.
type IssueContext struct {
	Repository   GQLRepository        `json:"repository"`
	Issue        GQLIssue             `json:"issue"`
	Participants []ContextParticipant `json:"-"`
}

// PullRequestContext represents a pull request context with repository and participant information.
type PullRequestContext struct {
	Repository              GQLRepository        `json:"repository"`
	PullRequest             GQLPullRequest       `json:"pull_request"`
	Participants            []ContextParticipant `json:"-"`
	ReviewThreadResolvedMap map[int64]bool       `json:"-"`
}

// GetReviewThreadResolvedMap returns the resolved map, preferring the separately-fetched
// map if available, otherwise falling back to building it from PullRequest.ReviewThreads.
func (c *PullRequestContext) GetReviewThreadResolvedMap() map[int64]bool {
	if c.ReviewThreadResolvedMap != nil {
		return c.ReviewThreadResolvedMap
	}
	return c.PullRequest.GetReviewThreadResolvedMap()
}

// ContextParticipant represents an actor in the context and
// includes their permissions on the associated repository.
type ContextParticipant struct {
	Actor       GQLActor               `json:"actor"`
	Permissions *RepositoryPermissions `json:"permissions,omitempty"`
}

//nolint:funcorder // Helper method is placed near callers for readability
func (i *IssueContext) getContextParticipants() []ContextParticipant {
	return i.Participants
}

//nolint:funcorder // Helper method is placed near callers for readability
func (p *PullRequestContext) getContextParticipants() []ContextParticipant {
	return p.Participants
}

// getParticipant returns the participant actor and their [RepositoryPermissions].
func getParticipant(c issueContext, actor GQLActor) *ContextParticipant {
	for _, p := range c.getContextParticipants() {
		if actorEqualFunc(p.Actor, actor) {
			return &p
		}
	}
	return nil
}

func uniqueParticipants(participants []GQLActor) []GQLActor {
	clone := slices.Clone(participants)
	// sort and deduplicate (get unique) participants
	slices.SortFunc(clone, actorSortFunc)
	return slices.CompactFunc(clone, actorEqualFunc)
}

// PermissionsFor returns the [RepositoryPermissions] for the given actor.
func (i *IssueContext) PermissionsFor(actor GQLActor) *RepositoryPermissions {
	p := getParticipant(i, actor)
	if p == nil {
		return nil
	}
	return p.Permissions
}

// PermissionsFor returns the [RepositoryPermissions] for the given actor.
func (p *PullRequestContext) PermissionsFor(actor GQLActor) *RepositoryPermissions {
	participant := getParticipant(p, actor)
	if participant == nil {
		return nil
	}
	return participant.Permissions
}

// AssignmentContextMaxCommentsDefault is the default maximum number of comments.
const AssignmentContextMaxCommentsDefault = 75

func getQueryVariables(repoNodeID string, number int) map[string]any {
	return map[string]any{
		"number":          githubv4.Int(number),
		"repoId":          githubv4.ID(repoNodeID),
		"maxAssignees":    githubv4.Int(10),
		"maxLabels":       githubv4.Int(20),
		"maxParticipants": githubv4.Int(20),
		"maxReactions":    githubv4.Int(20),
		"maxComments":     githubv4.Int(AssignmentContextMaxCommentsDefault),
	}
}

// GetRepositoryContext retrieves the repository context.
func (ac *Client) GetRepositoryContext(ctx context.Context, repoNodeID string) (*RepositoryContext, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetRepositoryContext")
	defer span.End()

	variables := map[string]any{
		"repoId": githubv4.ID(repoNodeID),
	}

	var q struct {
		Node struct {
			Context GQLRepositoryContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get repository context")
	}

	return &RepositoryContext{
		Repository: q.Node.Context.GQLRepository,
	}, nil
}

// GetIssueContext retrieves the issue context including participants.
func (ac *Client) GetIssueContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*IssueContext, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetIssueContext")
	defer span.End()

	variables := getQueryVariables(repoNodeID, number)

	var q struct {
		Node struct {
			Context GQLIssueContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get issue context")
	}

	c := &IssueContext{
		Repository: q.Node.Context.GQLRepository,
		Issue:      q.Node.Context.Issue,
	}

	actors, err := ac.getContextParticipants(ctx, c.Repository, c.Issue.GetParticipants(), isAgentic)
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

// UserContentEdit represents an edit to user content.
type UserContentEdit struct {
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	EditedAt  time.Time  `json:"edited_at"`
	DeletedAt *time.Time `json:"deleted_at,omitempty"`
	Diff      string     `json:"diff"`
	Editor    GQLActor   `json:"editor"`
	NodeID    string     `graphql:"id"                json:"node_id"`
}

// GetIssueUserContentEdits retrieves user content edits for an issue.
func (ac *Client) GetIssueUserContentEdits(ctx context.Context, issueNodeID string) ([]UserContentEdit, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetIssueUserContentEdits")
	defer span.End()

	var q struct {
		Node struct {
			Issue struct {
				UserContentEdits struct {
					Nodes []UserContentEdit
				} `graphql:"userContentEdits(first: 20)"`
			} `graphql:"... on Issue"`
		} `graphql:"node(id: $objectId)"`
	}

	variables := map[string]any{
		"objectId": githubv4.ID(issueNodeID),
	}

	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get issue user content edits")
	}

	return q.Node.Issue.UserContentEdits.Nodes, nil
}

// GetPullRequestContext retrieves the pull request context including participants.
func (ac *Client) GetPullRequestContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.GetPullRequestContext")
	defer span.End()

	// When the separate review threads flag is enabled, use the optimized query
	// that excludes ReviewThreads and fetches resolved status separately.
	if ac.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRContextSeparateReviewThreads) {
		return ac.getPullRequestContextWithoutReviewThreads(ctx, repoNodeID, number, isAgentic)
	}

	variables := getQueryVariables(repoNodeID, number)

	var q struct {
		Node struct {
			Context GQLPullRequestContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		// Check for resource limit errors first to avoid unnecessary error wrapping on the fallback path.
		if IsResourceLimitError(err) && ac.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRContextQueryFallback) {
			ac.obsv.LoggerWithTelemetry(ctx).Warn("PR context query exceeded resource limits, retrying with fallback query without reactions")
			return ac.getPullRequestContextFallback(ctx, repoNodeID, number, isAgentic)
		}

		return nil, ac.checkGQLError(ctx, err, "failed to get pull request context")
	}
	c := &PullRequestContext{
		Repository:  q.Node.Context.GQLRepository,
		PullRequest: q.Node.Context.PullRequest,
	}

	actors, err := ac.getContextParticipants(ctx, c.Repository, c.PullRequest.GetParticipants(), isAgentic)
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

func (ac *Client) getContextParticipants(ctx context.Context, repo GQLRepository, participants []GQLActor, isAgentic agenticapp.IsAgenticFunc) ([]ContextParticipant, error) {
	// get a list of unique participants and fetch repo permissions for each
	actors := []ContextParticipant{}
	for _, actor := range uniqueParticipants(participants) {
		var err error
		var permissions *RepositoryPermissions
		// The GraphQL API incorrectly returns "Copilot" as a participant of type User,
		// so the below `IsUser` check does not work as it returns true for copilot.
		_, isAgenticActor := isAgentic(actor)
		if actor.IsUser() && !isAgenticActor {
			// bots don't return permissions from the collaborators API, so only get them for users
			permissions, err = ac.GetUserPermissionsForRepository(ctx, repo.Owner.Login, repo.Name, actor.GetLogin())
			if err != nil {
				return actors, err
			}
		}
		actors = append(actors, ContextParticipant{
			Actor:       actor,
			Permissions: permissions,
		})
	}
	return actors, nil
}

// IsResourceLimitError checks if an error is a GraphQL resource limit error.
func IsResourceLimitError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "Resource limits for this query exceeded")
}

// fallbackPRComment is a comment type that omits reactions for the fallback query path.
// It embeds GqlCommentCore to share field definitions with GQLComment.
type fallbackPRComment struct {
	GqlCommentCore
}

func (c *fallbackPRComment) toGQLComment() GQLComment {
	return GQLComment{
		GqlCommentCore: c.GqlCommentCore,
	}
}

type fallbackPRIssueComment struct {
	fallbackPRComment
	GQLMinimizable
	URL string `json:"url"`
}

func (c *fallbackPRIssueComment) toGQLIssueComment() GQLIssueComment {
	return GQLIssueComment{
		GQLComment:     c.fallbackPRComment.toGQLComment(),
		GQLMinimizable: c.GQLMinimizable,
		URL:            c.URL,
	}
}

// fallbackPRReviewComment omits reactions and shares fields via GqlReviewCommentFields.
type fallbackPRReviewComment struct {
	fallbackPRComment
	GQLMinimizable
	GqlReviewCommentFields
}

func (c *fallbackPRReviewComment) toGQLPullRequestReviewComment() GQLPullRequestReviewComment {
	return GQLPullRequestReviewComment{
		GQLComment:             c.fallbackPRComment.toGQLComment(),
		GQLMinimizable:         c.GQLMinimizable,
		GqlReviewCommentFields: c.GqlReviewCommentFields,
	}
}

type fallbackPRReview struct {
	fallbackPRComment
	GQLMinimizable

	AuthorCanPushToRepository bool                                   `json:"author_can_push_to_repository"`
	Comments                  GQLConnection[fallbackPRReviewComment] `graphql:"comments(last: $maxComments)" json:"comments"`
	State                     GQLPullRequestReviewState              `json:"state"`
	SubmittedAt               time.Time                              `json:"submitted_at"`
	URL                       string                                 `json:"url"`
}

func (r *fallbackPRReview) toGQLPullRequestReview() GQLPullRequestReview {
	comments := make([]GQLPullRequestReviewComment, len(r.Comments.Nodes))
	for i := range r.Comments.Nodes {
		comments[i] = r.Comments.Nodes[i].toGQLPullRequestReviewComment()
	}
	return GQLPullRequestReview{
		GQLComment:                r.fallbackPRComment.toGQLComment(),
		GQLMinimizable:            r.GQLMinimizable,
		AuthorCanPushToRepository: r.AuthorCanPushToRepository,
		Comments: GQLConnection[GQLPullRequestReviewComment]{
			TotalCount: r.Comments.TotalCount,
			Nodes:      comments,
		},
		State:       r.State,
		SubmittedAt: r.SubmittedAt,
		URL:         r.URL,
	}
}

type fallbackPRReviewThread struct {
	IsResolved bool                                   `json:"is_resolved"`
	Comments   GQLConnection[fallbackPRReviewComment] `graphql:"comments(last: $maxComments)" json:"comments"`
}

func (t *fallbackPRReviewThread) toGQLPullRequestReviewThread() GQLPullRequestReviewThread {
	comments := make([]GQLPullRequestReviewComment, len(t.Comments.Nodes))
	for i := range t.Comments.Nodes {
		comments[i] = t.Comments.Nodes[i].toGQLPullRequestReviewComment()
	}
	return GQLPullRequestReviewThread{
		IsResolved: t.IsResolved,
		Comments: GQLConnection[GQLPullRequestReviewComment]{
			TotalCount: t.Comments.TotalCount,
			Nodes:      comments,
		},
	}
}

type fallbackPullRequest struct {
	fallbackPRComment
	GQLAssignable
	GQLCloseable
	GQLLabelable

	Title              string                                `json:"title"`
	Number             int                                   `json:"number"`
	IsDraft            bool                                  `json:"is_draft"`
	BaseRef            GQLRef                                `json:"base_ref"`
	HeadRef            GQLRef                                `json:"head_ref"`
	Participants       GQLConnection[GQLUser]                `graphql:"participants(first: $maxParticipants)" json:"participants"`
	Comments           GQLConnection[fallbackPRIssueComment] `graphql:"comments(last: $maxComments)"          json:"comments"`
	Reviews            GQLConnection[fallbackPRReview]       `graphql:"reviews(last: $maxComments)"           json:"reviews"`
	ReviewThreads      GQLConnection[fallbackPRReviewThread] `graphql:"reviewThreads(last: $maxComments)"     json:"review_threads"`
	TotalCommentsCount int                                   `json:"total_comments_count"`
	IsCrossRepository  bool                                  `json:"is_cross_repository"`
	Commits            struct {
		TotalCount int `json:"total_count"`
	} `json:"commits"`
}

func (pr *fallbackPullRequest) toGQLPullRequest() GQLPullRequest {
	comments := make([]GQLIssueComment, len(pr.Comments.Nodes))
	for i := range pr.Comments.Nodes {
		comments[i] = pr.Comments.Nodes[i].toGQLIssueComment()
	}
	reviews := make([]GQLPullRequestReview, len(pr.Reviews.Nodes))
	for i := range pr.Reviews.Nodes {
		reviews[i] = pr.Reviews.Nodes[i].toGQLPullRequestReview()
	}
	reviewThreads := make([]GQLPullRequestReviewThread, len(pr.ReviewThreads.Nodes))
	for i := range pr.ReviewThreads.Nodes {
		reviewThreads[i] = pr.ReviewThreads.Nodes[i].toGQLPullRequestReviewThread()
	}
	return GQLPullRequest{
		GQLComment:    pr.fallbackPRComment.toGQLComment(),
		GQLAssignable: pr.GQLAssignable,
		GQLCloseable:  pr.GQLCloseable,
		GQLLabelable:  pr.GQLLabelable,
		Title:         pr.Title,
		Number:        pr.Number,
		IsDraft:       pr.IsDraft,
		BaseRef:       pr.BaseRef,
		HeadRef:       pr.HeadRef,
		Participants:  pr.Participants,
		Comments: GQLConnection[GQLIssueComment]{
			TotalCount: pr.Comments.TotalCount,
			Nodes:      comments,
		},
		Reviews: GQLConnection[GQLPullRequestReview]{
			TotalCount: pr.Reviews.TotalCount,
			Nodes:      reviews,
		},
		ReviewThreads: GQLConnection[GQLPullRequestReviewThread]{
			TotalCount: pr.ReviewThreads.TotalCount,
			Nodes:      reviewThreads,
		},
		TotalCommentsCount: pr.TotalCommentsCount,
		IsCrossRepository:  pr.IsCrossRepository,
		Commits:            pr.Commits,
	}
}

type fallbackPRContext struct {
	GQLRepository

	PullRequest fallbackPullRequest `graphql:"pullRequest(number: $number)" json:"pull_request"`
}

func (ac *Client) getPullRequestContextFallback(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error) {
	// Use the same variables as the original query, minus maxReactions
	variables := map[string]any{
		"number":          githubv4.Int(number),
		"repoId":          githubv4.ID(repoNodeID),
		"maxAssignees":    githubv4.Int(10),
		"maxLabels":       githubv4.Int(20),
		"maxParticipants": githubv4.Int(20),
		"maxComments":     githubv4.Int(AssignmentContextMaxCommentsDefault),
	}

	var q struct {
		Node struct {
			Context fallbackPRContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get pull request context (fallback)")
	}

	pr := q.Node.Context.PullRequest.toGQLPullRequest()
	c := &PullRequestContext{
		Repository:  q.Node.Context.GQLRepository,
		PullRequest: pr,
	}

	actors, err := ac.getContextParticipants(ctx, c.Repository, c.PullRequest.GetParticipants(), isAgentic)
	if err != nil {
		return nil, err
	}
	c.Participants = actors

	return c, nil
}

// pullRequestWithoutReviewThreads is identical to GQLPullRequest but without the ReviewThreads field.
// Used when CopilotSWEAgentPRContextSeparateReviewThreads is enabled to reduce node count.
type pullRequestWithoutReviewThreads struct {
	GQLComment
	GQLAssignable
	GQLCloseable
	GQLLabelable

	Title              string                              `json:"title"`
	Number             int                                 `json:"number"`
	IsDraft            bool                                `json:"is_draft"`
	BaseRef            GQLRef                              `json:"base_ref"`
	HeadRef            GQLRef                              `json:"head_ref"`
	Participants       GQLConnection[GQLUser]              `graphql:"participants(first: $maxParticipants)" json:"participants"`
	Comments           GQLConnection[GQLIssueComment]      `graphql:"comments(last: $maxComments)"          json:"comments"`
	Reviews            GQLConnection[GQLPullRequestReview] `graphql:"reviews(last: $maxComments)"           json:"reviews"`
	TotalCommentsCount int                                 `json:"total_comments_count"`
	IsCrossRepository  bool                                `json:"is_cross_repository"`
	Commits            struct {
		TotalCount int `json:"total_count"`
	} `json:"commits"`
}

func (pr *pullRequestWithoutReviewThreads) toGQLPullRequest() GQLPullRequest {
	return GQLPullRequest{
		GQLComment:         pr.GQLComment,
		GQLAssignable:      pr.GQLAssignable,
		GQLCloseable:       pr.GQLCloseable,
		GQLLabelable:       pr.GQLLabelable,
		Title:              pr.Title,
		Number:             pr.Number,
		IsDraft:            pr.IsDraft,
		BaseRef:            pr.BaseRef,
		HeadRef:            pr.HeadRef,
		Participants:       pr.Participants,
		Comments:           pr.Comments,
		Reviews:            pr.Reviews,
		TotalCommentsCount: pr.TotalCommentsCount,
		IsCrossRepository:  pr.IsCrossRepository,
		Commits:            pr.Commits,
	}
}

type pullRequestWithoutReviewThreadsContext struct {
	GQLRepository

	PullRequest pullRequestWithoutReviewThreads `graphql:"pullRequest(number: $number)" json:"pull_request"`
}

// fallbackPullRequestWithoutReviewThreads is the fallback (no reactions) variant without ReviewThreads.
type fallbackPullRequestWithoutReviewThreads struct {
	fallbackPRComment
	GQLAssignable
	GQLCloseable
	GQLLabelable

	Title              string                                `json:"title"`
	Number             int                                   `json:"number"`
	IsDraft            bool                                  `json:"is_draft"`
	BaseRef            GQLRef                                `json:"base_ref"`
	HeadRef            GQLRef                                `json:"head_ref"`
	Participants       GQLConnection[GQLUser]                `graphql:"participants(first: $maxParticipants)" json:"participants"`
	Comments           GQLConnection[fallbackPRIssueComment] `graphql:"comments(last: $maxComments)"          json:"comments"`
	Reviews            GQLConnection[fallbackPRReview]       `graphql:"reviews(last: $maxComments)"           json:"reviews"`
	TotalCommentsCount int                                   `json:"total_comments_count"`
	IsCrossRepository  bool                                  `json:"is_cross_repository"`
	Commits            struct {
		TotalCount int `json:"total_count"`
	} `json:"commits"`
}

func (pr *fallbackPullRequestWithoutReviewThreads) toGQLPullRequest() GQLPullRequest {
	comments := make([]GQLIssueComment, len(pr.Comments.Nodes))
	for i := range pr.Comments.Nodes {
		comments[i] = pr.Comments.Nodes[i].toGQLIssueComment()
	}
	reviews := make([]GQLPullRequestReview, len(pr.Reviews.Nodes))
	for i := range pr.Reviews.Nodes {
		reviews[i] = pr.Reviews.Nodes[i].toGQLPullRequestReview()
	}
	return GQLPullRequest{
		GQLComment:    pr.fallbackPRComment.toGQLComment(),
		GQLAssignable: pr.GQLAssignable,
		GQLCloseable:  pr.GQLCloseable,
		GQLLabelable:  pr.GQLLabelable,
		Title:         pr.Title,
		Number:        pr.Number,
		IsDraft:       pr.IsDraft,
		BaseRef:       pr.BaseRef,
		HeadRef:       pr.HeadRef,
		Participants:  pr.Participants,
		Comments: GQLConnection[GQLIssueComment]{
			TotalCount: pr.Comments.TotalCount,
			Nodes:      comments,
		},
		Reviews: GQLConnection[GQLPullRequestReview]{
			TotalCount: pr.Reviews.TotalCount,
			Nodes:      reviews,
		},
		TotalCommentsCount: pr.TotalCommentsCount,
		IsCrossRepository:  pr.IsCrossRepository,
		Commits:            pr.Commits,
	}
}

type fallbackPullRequestWithoutReviewThreadsContext struct {
	GQLRepository

	PullRequest fallbackPullRequestWithoutReviewThreads `graphql:"pullRequest(number: $number)" json:"pull_request"`
}

// reviewThreadResolvedComment is a lightweight comment type that only fetches the database ID.
type reviewThreadResolvedComment struct {
	ID FullDatabaseID `graphql:"fullDatabaseId" json:"id"`
}

// reviewThreadResolved is a lightweight review thread type for the separate resolved-map query.
type reviewThreadResolved struct {
	IsResolved bool                                       `json:"is_resolved"`
	Comments   GQLConnection[reviewThreadResolvedComment] `graphql:"comments(last: $maxComments)" json:"comments"`
}

type reviewThreadResolvedQuery struct {
	PullRequest struct {
		ReviewThreads GQLConnection[reviewThreadResolved] `graphql:"reviewThreads(last: $maxComments)" json:"review_threads"`
	} `graphql:"pullRequest(number: $number)" json:"pull_request"`
}

// getReviewThreadResolvedMap fetches only the review thread resolved status and comment IDs
// via a lightweight separate GraphQL query.
func (ac *Client) getReviewThreadResolvedMap(ctx context.Context, repoNodeID string, number int) (map[int64]bool, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.getReviewThreadResolvedMap")
	defer span.End()

	variables := map[string]any{
		"number":      githubv4.Int(number),
		"repoId":      githubv4.ID(repoNodeID),
		"maxComments": githubv4.Int(AssignmentContextMaxCommentsDefault),
	}

	var q struct {
		Node struct {
			Context reviewThreadResolvedQuery `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}

	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get review thread resolved map")
	}

	resolvedMap := make(map[int64]bool)
	for _, thread := range q.Node.Context.PullRequest.ReviewThreads.Nodes {
		for _, comment := range thread.Comments.Nodes {
			resolvedMap[comment.ID.int64()] = thread.IsResolved
		}
	}
	return resolvedMap, nil
}

// getPullRequestContextWithoutReviewThreads fetches the PR context without ReviewThreads (primary query with reactions).
func (ac *Client) getPullRequestContextWithoutReviewThreads(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error) {
	variables := getQueryVariables(repoNodeID, number)

	var q struct {
		Node struct {
			Context pullRequestWithoutReviewThreadsContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		if IsResourceLimitError(err) && ac.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentPRContextQueryFallback) {
			ac.obsv.LoggerWithTelemetry(ctx).Warn("optimized PR context query exceeded resource limits, retrying with fallback query without reactions")
			return ac.getPullRequestContextWithoutReviewThreadsFallback(ctx, repoNodeID, number, isAgentic)
		}
		return nil, ac.checkGQLError(ctx, err, "failed to get pull request context (without review threads)")
	}

	pr := q.Node.Context.PullRequest.toGQLPullRequest()
	c := &PullRequestContext{
		Repository:  q.Node.Context.GQLRepository,
		PullRequest: pr,
	}

	// Fetch participants and review thread resolved map concurrently since they're independent.
	g, gctx := errgroup.WithContext(ctx)

	g.Go(func() error {
		actors, err := ac.getContextParticipants(gctx, c.Repository, c.PullRequest.GetParticipants(), isAgentic)
		if err != nil {
			return err
		}
		c.Participants = actors
		return nil
	})

	g.Go(func() error {
		resolvedMap, err := ac.getReviewThreadResolvedMap(gctx, repoNodeID, number)
		if err != nil {
			return err
		}
		c.ReviewThreadResolvedMap = resolvedMap
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return c, nil
}

// getPullRequestContextWithoutReviewThreadsFallback fetches the PR context without ReviewThreads and without reactions.
func (ac *Client) getPullRequestContextWithoutReviewThreadsFallback(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*PullRequestContext, error) {
	variables := map[string]any{
		"number":          githubv4.Int(number),
		"repoId":          githubv4.ID(repoNodeID),
		"maxAssignees":    githubv4.Int(10),
		"maxLabels":       githubv4.Int(20),
		"maxParticipants": githubv4.Int(20),
		"maxComments":     githubv4.Int(AssignmentContextMaxCommentsDefault),
	}

	var q struct {
		Node struct {
			Context fallbackPullRequestWithoutReviewThreadsContext `graphql:"... on Repository"`
		} `graphql:"node(id: $repoId)"`
	}
	err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
	if err != nil {
		return nil, ac.checkGQLError(ctx, err, "failed to get pull request context (without review threads, fallback)")
	}

	pr := q.Node.Context.PullRequest.toGQLPullRequest()
	c := &PullRequestContext{
		Repository:  q.Node.Context.GQLRepository,
		PullRequest: pr,
	}

	// Fetch participants and review thread resolved map concurrently since they're independent.
	g, gctx := errgroup.WithContext(ctx)

	g.Go(func() error {
		actors, err := ac.getContextParticipants(gctx, c.Repository, c.PullRequest.GetParticipants(), isAgentic)
		if err != nil {
			return err
		}
		c.Participants = actors
		return nil
	})

	g.Go(func() error {
		resolvedMap, err := ac.getReviewThreadResolvedMap(gctx, repoNodeID, number)
		if err != nil {
			return err
		}
		c.ReviewThreadResolvedMap = resolvedMap
		return nil
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return c, nil
}

type FilterCommentOpts struct {
	// If true, includes minimized comments
	IncludeMinimized bool
	// If true, includes comments from bots other than Copilot
	IncludeOtherBots bool
	// If true, includes comments from users without push permissions
	IncludeUsersWithoutPushPermissions bool
	// If true, includes Copilot reviews
	IncludeCopilotReviews bool
}

// FilteredComments returns a copy of the issue comments slice with comments
// that should be filtered out removed.
func (i *IssueContext) FilteredComments(opts FilterCommentOpts, isAgentic agenticapp.IsAgenticFunc) []GQLIssueComment {
	return filteredComments(i, opts, i.Issue.Comments.Nodes, isAgentic)
}

// FilteredComments returns a copy of the pull request comments slice
// with comments that should be filtered out removed.
func (p *PullRequestContext) FilteredComments(opts FilterCommentOpts, isAgentic agenticapp.IsAgenticFunc) []GQLIssueComment {
	return filteredComments(p, opts, p.PullRequest.Comments.Nodes, isAgentic)
}

// FilteredReviews returns a copy of the pull request reviews slice
// with reviews that should be filtered out removed.
func (p *PullRequestContext) FilteredReviews(opts FilterCommentOpts, isAgentic agenticapp.IsAgenticFunc) []GQLPullRequestReview {
	reviews := filteredComments(p, opts, p.PullRequest.Reviews.Nodes, isAgentic)
	for i := range reviews {
		reviews[i].Comments.Nodes = filteredComments(p, opts, reviews[i].Comments.Nodes, isAgentic)
	}
	return reviews
}

// ReviewOrReviewComment represents a review or review comment.
type ReviewOrReviewComment interface {
	GetBody() string
	GetURL() string
}

// ReviewOrComment represents a review or comment that can be minimized.
type ReviewOrComment interface {
	Comment
	Minimizable
	IsReview() bool
}

// IsReview returns false for issue comments.
func (c GQLIssueComment) IsReview() bool {
	return false
}

// IsReview returns true for pull request reviews.
func (r GQLPullRequestReview) IsReview() bool {
	return true
}

// IsReview returns true for pull request review comments.
func (r GQLPullRequestReviewComment) IsReview() bool {
	return true
}

// filteredComments returns a copy of the comments slice with comments that should be filtered out removed.
func filteredComments[S ~[]E, E ReviewOrComment](c issueContext, opts FilterCommentOpts, comments S, isAgentic agenticapp.IsAgenticFunc) S {
	// returns true if the comment should be filtered out based on the minimized state.
	filterMinimized := func(m E) bool { return !opts.IncludeMinimized && m.GetIsMinimized() }

	// returns true if comments and reviews should be filtered out based on the actor.
	filterParticipant := func(e E) bool {
		a := e.GetAuthor()
		participant := getParticipant(c, a)
		if participant == nil {
			// if we don't have the participant for some reason
			// (shouldn't happen) we shouldn't include their comments
			return true
		}
		_, isAgenticActor := isAgentic(participant.Actor)

		switch {
		case isAgenticActor:
			// we want to include comments from Copilot, but not reviews unless IncludeCopilotReviews is true
			if e.IsReview() {
				return !opts.IncludeCopilotReviews
			}
			return false
		case participant.Actor.IsUser():
			if participant.Permissions == nil {
				return !opts.IncludeUsersWithoutPushPermissions
			}
			return !participant.Permissions.Push && !opts.IncludeUsersWithoutPushPermissions
		case agenticapp.IsAllowlistedBot(participant.Actor):
			// There are some bots we want to always include comments from
			// namely CCR
			return false
		case participant.Actor.IsBot():
			return !opts.IncludeOtherBots
		default:
			return true
		}
	}

	// create a clone of the comments slice
	clone := slices.Clone(comments)

	// remove comments that should be filtered out
	clone = slices.DeleteFunc(clone, func(i E) bool {
		return filterMinimized(i) || filterParticipant(i)
	})

	return clone
}

// MarkPullRequestReadyForReview marks a pull request as ready for review.
func (ac *Client) MarkPullRequestReadyForReview(ctx context.Context, prNodeID string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.MarkPullRequestReadyForReview")
	defer span.End()

	var m struct {
		MarkPullRequestReadyForReview struct {
			PullRequest struct {
				ID      FullDatabaseID `graphql:"fullDatabaseId" json:"id"`
				NodeID  string         `graphql:"id"             json:"node_id"`
				IsDraft bool           `json:"is_draft"`
			}
		} `graphql:"markPullRequestReadyForReview(input: $input)"`
	}
	input := githubv4.MarkPullRequestReadyForReviewInput{
		PullRequestID: githubv4.ID(prNodeID),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to mark pull request ready for review")
	}
	return nil
}

// ConvertPullRequestToDraft converts a pull request to draft.
func (ac *Client) ConvertPullRequestToDraft(ctx context.Context, prNodeID string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ConvertPullRequestToDraft")
	defer span.End()

	var m struct {
		ConvertPullRequestToDraft struct {
			PullRequest struct {
				ID      FullDatabaseID `graphql:"fullDatabaseId" json:"id"`
				NodeID  string         `graphql:"id"             json:"node_id"`
				IsDraft bool           `json:"is_draft"`
			}
		} `graphql:"convertPullRequestToDraft(input: $input)"`
	}
	input := githubv4.ConvertPullRequestToDraftInput{
		PullRequestID: githubv4.ID(prNodeID),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to convert pull request to draft")
	}
	return nil
}

// AddReaction adds a reaction to a subject.
func (ac *Client) AddReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.AddReaction")
	defer span.End()

	var m struct {
		AddReaction struct {
			Reaction struct {
				Content string `json:"content"`
			}
		} `graphql:"addReaction(input: $input)"`
	}
	input := githubv4.AddReactionInput{
		SubjectID: githubv4.ID(nodeID),
		Content:   githubv4.ReactionContent(content),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to add reaction")
	}
	return nil
}

// RemoveReaction removes a reaction from a subject.
func (ac *Client) RemoveReaction(ctx context.Context, nodeID string, content GQLReactionContent) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.RemoveReaction")
	defer span.End()

	var m struct {
		RemoveReaction struct {
			Reaction struct {
				Content string `json:"content"`
			}
		} `graphql:"removeReaction(input: $input)"`
	}
	input := githubv4.RemoveReactionInput{
		SubjectID: githubv4.ID(nodeID),
		Content:   githubv4.ReactionContent(content),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to remove reaction")
	}
	return nil
}

// MinimizeComment minimizes a comment with the given classifier.
func (ac *Client) MinimizeComment(ctx context.Context, nodeID string, classifier GQLReportedContentClassifier) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.MinimizeComment")
	defer span.End()

	var m struct {
		MinimizeComment struct {
			MinimizedComment struct {
				IsMinimized bool `json:"is_minimized"`
			}
		} `graphql:"minimizeComment(input: $input)"`
	}
	input := githubv4.MinimizeCommentInput{
		SubjectID:  githubv4.ID(nodeID),
		Classifier: githubv4.ReportedContentClassifiers(classifier),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to minimize comment")
	}
	return nil
}

// UnminimizeComment unminimizes a comment.
func (ac *Client) UnminimizeComment(ctx context.Context, nodeID string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.UnminimizeComment")
	defer span.End()

	var m struct {
		UnminimizeComment struct {
			UnminimizedComment struct {
				IsMinimized bool `json:"is_minimized"`
			}
		} `graphql:"unminimizeComment(input: $input)"`
	}
	input := githubv4.UnminimizeCommentInput{
		SubjectID: githubv4.ID(nodeID),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to unminimize comment")
	}
	return nil
}

// ReplaceActorsForAssignableInput represents the input for replacing actors on an assignable.
type ReplaceActorsForAssignableInput struct {
	// The Node ID of the issue or PR to be assigned to. (Required.)
	AssignableID githubv4.ID `json:"assignableId"`
	// The Node ID of the participant to assign to. (Required.)
	ActorIDs []githubv4.ID `json:"actorIds"`
	// A unique identifier for the client performing the mutation. (Optional.)
	ClientMutationID *githubv4.String `json:"clientMutationId,omitempty"`
}

// ReplaceActorsForAssignable allows for assigning a user or app[bot] to a pull request or issue.
// The mutation will replace all current assignees with the provided list of assignees.
// https://docs.github.com/en/graphql/reference/mutations#replaceactorsforassignable
func (ac *Client) ReplaceActorsForAssignable(ctx context.Context, assignableID string, actorIDs []string) error {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ReplaceActorsForAssignable")
	defer span.End()

	var m struct {
		ReplaceActorsForAssignable struct {
			Assignable struct {
				Type string `graphql:"__typename"`
			} `json:"assignable"`
		} `graphql:"replaceActorsForAssignable(input: $input)"`
	}
	input := ReplaceActorsForAssignableInput{
		AssignableID: githubv4.ID(assignableID),
		ActorIDs:     convertStringsToGithubv4IDs(actorIDs),
	}

	err := ac.getGraphQLClient(ctx).Mutate(ctx, &m, input, nil)
	if err != nil {
		return ac.checkGQLError(ctx, err, "failed to replace actors for assignable")
	}
	return nil
}

func convertStringsToGithubv4IDs(ids []string) []githubv4.ID {
	var githubIDs []githubv4.ID

	for _, id := range ids {
		githubIDs = append(githubIDs, githubv4.ID(id))
	}

	return githubIDs
}

// GQLBranchProtectionRule represents a branch protection rule.
type GQLBranchProtectionRule struct {
	ID                       string `graphql:"id"                       json:"id"`
	Pattern                  string `graphql:"pattern"                  json:"pattern"`
	BlocksCreations          bool   `graphql:"blocksCreations"          json:"blocksCreations"`
	RequiresCommitSignatures bool   `graphql:"requiresCommitSignatures" json:"requiresCommitSignatures"`
	RequiresApprovingReviews bool   `graphql:"requiresApprovingReviews" json:"requiresApprovingReviews"`
}

// ListBranchProtectionRules lists all branch protection rules for a repository.
// https://docs.github.com/en/graphql/reference/objects#branchprotectionrule
func (ac *Client) ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]GQLBranchProtectionRule, error) {
	ctx, span := ac.obsv.Tracer.Start(ctx, "github.Client.ListBranchProtectionRules")
	defer span.End()

	// Using max for page size https://docs.github.com/en/graphql/guides/using-pagination-in-the-graphql-api
	const pageSize = 100
	var allRules []GQLBranchProtectionRule
	var after *githubv4.String

	for {
		var q struct {
			Node struct {
				Repository struct {
					BranchProtectionRules struct {
						Nodes    []GQLBranchProtectionRule
						PageInfo struct {
							HasNextPage bool
							EndCursor   githubv4.String
						}
					} `graphql:"branchProtectionRules(first: $first, after: $after)"`
				} `graphql:"... on Repository"`
			} `graphql:"node(id: $repoId)"`
		}

		variables := map[string]any{
			"repoId": githubv4.ID(repoNodeID),
			"first":  githubv4.Int(pageSize),
			"after":  after,
		}

		err := ac.getGraphQLClient(ctx).Query(ctx, &q, variables)
		if err != nil {
			return nil, ac.checkGQLError(ctx, err, "failed to list branch protection rules")
		}

		allRules = append(allRules, q.Node.Repository.BranchProtectionRules.Nodes...)

		if !q.Node.Repository.BranchProtectionRules.PageInfo.HasNextPage {
			break
		}
		after = &q.Node.Repository.BranchProtectionRules.PageInfo.EndCursor
	}

	return &allRules, nil
}
