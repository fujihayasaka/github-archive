package flowevents

import (
	"context"
	"strings"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
)

// GetEventTypeGlobs gets the default type/action globs for a given event
func GetEventTypeGlobs(eventName string) []string {
	n := strings.ToLower(eventName)
	info, ok := eventsAllowed[n]
	if ok {
		return info.defaultTypes
	}
	return nil
}

// IsAllowedEvent returns true if the event is supported by our flowfiles
func IsAllowedEvent(eventName string) bool {
	n := strings.ToLower(eventName)
	_, ok := eventsAllowed[n]
	return ok
}

func AreSecretsEnabled(eventName string) bool {
	n := strings.ToLower(eventName)
	info, ok := eventsAllowed[n]
	return ok && info.secretsEnabled
}

func IsAllowedWebhookEvent(eventName string) bool {
	n := strings.ToLower(eventName)
	info, ok := eventsAllowed[n]
	return ok && !info.nonWebhookEvent
}

func IsWorkflowRunEvent(eventName string) bool {
	return strings.EqualFold(WorkflowRun, eventName)
}

// IsWorkflowDispatchEvent returns true if the eventType is a Workflow Dispatch event
func IsWorkflowDispatchEvent(eventName string) bool {
	return strings.EqualFold(WorkflowDispatch, eventName)
}

func ResolveSyntheticEventName(eventName string) string {
	if eventName == PullRequestTarget {
		return PullRequest
	}
	return eventName
}

// GetDependabotRestrictionLevel returns a restriction level for determining token permissions and the appropriate secret store.
func GetDependabotRestrictionLevel(ctx context.Context, obs *observability.Observability, eventName string) DependabotRestrictionLevel {
	n := strings.ToLower(eventName)
	info, ok := eventsAllowed[n]
	if !ok {
		obs.Logger.Error(ctx, "Event type unknown. Using full dependabot restrictions", kvp.String("gh.launch.event.name", eventName))
		return DependabotActorNotExpected
	}

	return info.dependabotRestrictions
}

// webhook events
const (
	BranchProtectionRule     = "branch_protection_rule"
	CheckRun                 = "check_run"
	CheckSuite               = "check_suite"
	Create                   = "create"
	Delete                   = "delete"
	Deployment               = "deployment"
	DeploymentStatus         = "deployment_status"
	Discussion               = "discussion"
	DiscussionComment        = "discussion_comment"
	Fork                     = "fork"
	Gollum                   = "gollum"
	InteractiveComponent     = "interactive_component"
	IssueComment             = "issue_comment"
	Issues                   = "issues"
	Label                    = "label"
	Member                   = "member"
	MergeGroup               = "merge_group"
	Milestone                = "milestone"
	RegistryPackage          = "registry_package"
	PageBuild                = "page_build"
	ProjectCard              = "project_card"
	ProjectColumn            = "project_column"
	Project                  = "project"
	Public                   = "public"
	PullRequestReviewComment = "pull_request_review_comment"
	PullRequestReview        = "pull_request_review"
	PullRequest              = "pull_request"
	PullRequestTarget        = "pull_request_target"
	Push                     = "push"
	Release                  = "release"
	RepositoryDispatch       = "repository_dispatch"
	Status                   = "status"
	Watch                    = "watch"
	WorkflowRun              = "workflow_run"
	WorkflowDispatch         = "workflow_dispatch"
)

// non-webhook events
const (
	Dynamic      = "dynamic"
	Schedule     = "schedule"
	WorkflowCall = "workflow_call"
)

// webhook event actions
const (
	PullRequestClosedAction  = "closed"
	PullRequestLabeledAction = "labeled"
)

type DependabotRestrictionLevel string

const (
	// It's not expected that Dependabot will trigger this event. Event should be fully restricted; see GetDependabotRestrictionLevel.
	DependabotActorNotExpected DependabotRestrictionLevel = ""

	// DependabotFullyRestricted indicates no secrets and a GITHUB_TOKEN with limited read-only permissions should be used for this event
	DependabotFullyRestricted DependabotRestrictionLevel = "fully_restricted"

	// DependabotPartiallyRestricted indicates Dependabot secrets and a read-only GITHUB_TOKEN should be used for this event
	DependabotPartiallyRestricted DependabotRestrictionLevel = "partially_restricted"

	// DependabotUnrestricted indicates Actions secrets and the default GITHUB_TOKEN policy should be used for this event
	DependabotUnrestricted DependabotRestrictionLevel = "unrestricted"
)

type eventInfo struct {
	defaultTypes           []string
	secretsEnabled         bool
	dependabotRestrictions DependabotRestrictionLevel
	nonWebhookEvent        bool
}

var eventsAllowed = map[string]eventInfo{
	// Webhook events
	BranchProtectionRule:     {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	CheckRun:                 {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	CheckSuite:               {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Create:                   {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	Delete:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Deployment:               {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	DeploymentStatus:         {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	Discussion:               {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	DiscussionComment:        {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Fork:                     {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Gollum:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	InteractiveComponent:     {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	IssueComment:             {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Issues:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Label:                    {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Member:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	MergeGroup:               {secretsEnabled: true, dependabotRestrictions: DependabotActorNotExpected, defaultTypes: []string{"checks_requested"}},
	Milestone:                {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	RegistryPackage:          {secretsEnabled: true, dependabotRestrictions: DependabotActorNotExpected},
	PageBuild:                {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	ProjectCard:              {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	ProjectColumn:            {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Project:                  {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Public:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	PullRequestReviewComment: {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	PullRequestReview:        {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	PullRequest:              {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted, defaultTypes: []string{"opened", "reopened", "synchronize"}},
	PullRequestTarget:        {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted, defaultTypes: []string{"opened", "reopened", "synchronize"}},
	Push:                     {secretsEnabled: true, dependabotRestrictions: DependabotPartiallyRestricted},
	Release:                  {secretsEnabled: true, dependabotRestrictions: DependabotActorNotExpected},
	RepositoryDispatch:       {secretsEnabled: true, dependabotRestrictions: DependabotActorNotExpected},
	Status:                   {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	Watch:                    {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	WorkflowRun:              {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted},
	WorkflowDispatch:         {secretsEnabled: true, dependabotRestrictions: DependabotActorNotExpected},
	// Non-webhook events
	Schedule:     {secretsEnabled: true, dependabotRestrictions: DependabotUnrestricted, nonWebhookEvent: true},
	Dynamic:      {secretsEnabled: true, dependabotRestrictions: DependabotFullyRestricted, nonWebhookEvent: true},
	WorkflowCall: {secretsEnabled: false, dependabotRestrictions: DependabotFullyRestricted, nonWebhookEvent: true},
}
