package oidc

import (
	"context"
	"fmt"
	"time"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// DefaultTokenExpiry is the default lifetime for issued OIDC tokens.
	DefaultTokenExpiry = 5 * time.Minute
)

// TokenSigner issues signed OIDC ID tokens and optionally exposes the public key
// metadata needed for OIDC discovery (JWKS) endpoints.
type TokenSigner interface {
	IssueIDToken(ctx context.Context, audience, subject, actSubject string, additionalClaims map[string]string) (string, error)
}

// TokenParams contains the contextual information used to build OIDC token claims.
type TokenParams struct {
	ActorID            int64
	Actor              string
	ActorType          jobs.ActorType
	OwnerID            int64
	Owner              string
	OwnerType          sweagentd.OwnerType // The type of the repository owner (user or organization)
	RepoID             int64
	Repo               string
	AppID              int64
	AppClientID        string // The OAuth client ID for the agentic app (used in BuildSubject for agent identity).
	PlatformClientID   string // The OAuth client ID for the platform app (CCA), always used as the client_id claim.
	AppInstallationID  int64  // Installation ID for the agentic app, if applicable.
	SessionID          string // The session ID for the current agent job
	CustomAgentName    string // Custom agent name, if applicable.
	CustomAgentVersion string // Custom agent version or SHA, if applicable.
}

// ToClaimsMap returns the standard claims derived from the token params.
// These are always included in OIDC tokens alongside any integrator-specified claims.
func (p TokenParams) ToClaimsMap() map[string]string {
	claims := map[string]string{
		"repository":          p.Repo,
		"repository_id":       fmt.Sprintf("%d", p.RepoID),
		"repository_owner":    p.Owner,
		"repository_owner_id": fmt.Sprintf("%d", p.OwnerID),
		"client_id":           p.PlatformClientID,
		"session_id":          p.SessionID,
	}
	if p.AppClientID != "" && p.AppClientID != p.PlatformClientID {
		claims["agent_client_id"] = p.AppClientID
		claims["agent_id"] = fmt.Sprintf("%d", p.AppID)
	}
	if !p.actorIsAgent() {
		claims["preferred_username"] = p.Actor
		claims["user_id"] = fmt.Sprintf("%d", p.ActorID)
	}
	if p.AppInstallationID > 0 {
		claims["installation_id"] = fmt.Sprintf("%d", p.AppInstallationID)
	}
	return claims
}

// actorIsAgent reports whether the actor is a bot or agent (not a human user).
func (p TokenParams) actorIsAgent() bool {
	// Actor is considered an agent if its type is not a user, so we will also treat not set as a user.
	// Old records with an actor type not set are user actors (since we didn't have actor types initially)
	return p.ActorType != "" && p.ActorType != jobs.ActorTypeUser
}

// SubjectOptions controls how BuildSubject composes the sub and act.sub claims.
type SubjectOptions struct {
	// AgentOnlySubject forces the sub to use the agent identity even when a
	// human user is present.
	AgentOnlySubject bool
	// RepoOnlySubject sets the sub to just the repository identity.
	RepoOnlySubject bool
	// UseAgenticAppIdentity indicates that this entry should use the agentic app's
	// identity (installation ID or agent client ID). When false, the platform
	// (CCA) identity is used instead.
	UseAgenticAppIdentity bool
}

// BuildSubject composes the OIDC subject values based on the provided options.
//
// It returns the `sub` claim first and the `act.sub` claim second.
//
// The `act.sub` always identifies the agent: if an installation ID is present
// the format is "installation_id:{id}", otherwise it uses
// "client_id:{client_id}:owner_id:{type}:{id}". When AgentName is set, it is
// appended as ":agent:{name}:{version}".
//
// The `sub` is determined by the options:
//   - RepoOnlySubject: "repository_id:{repository_id}"
//   - AgentOnlySubject false + valid human user: "user_id:{user_id}"
//   - Otherwise: agent identity based on UseAgentIdentity (uses agentic app
//     identity when true, platform identity when false)
func BuildSubject(opts SubjectOptions, params TokenParams) (sub, actSub string) {
	// Build the agent identity for act.sub, respecting useAgenticAppIdentity
	actSub = buildAgentActorSubject(opts.UseAgenticAppIdentity, params, true)

	if opts.RepoOnlySubject {
		if opts.UseAgenticAppIdentity && params.AppInstallationID > 0 {
			return fmt.Sprintf("installation_id:%d:repository_id:%d", params.AppInstallationID, params.RepoID), actSub
		}
		return fmt.Sprintf("client_id:%s:repository_id:%d", params.PlatformClientID, params.RepoID), actSub
	}

	if params.ActorID != 0 && !params.actorIsAgent() && !opts.AgentOnlySubject {
		return fmt.Sprintf("user_id:%d", params.ActorID), actSub
	}

	// Build the sub identity based on whether we should use agent app identity or platform identity
	sub = buildAgentSubject(opts.UseAgenticAppIdentity, params)
	return sub, actSub
}

// buildAgentActorSubject constructs the agent identity string including optional
// custom agent name and version. It uses useAgentIdentity to decide whether to
// use the agentic app's identity or the platform identity as the base, then
// appends "custom_agent:{repo_id}:{name}@{version}" when applicable.
func buildAgentActorSubject(useAgentIdentity bool, params TokenParams, includeCustomAgentSuffix bool) string {
	base := buildAgentSubject(useAgentIdentity, params)

	if includeCustomAgentSuffix && params.CustomAgentName != "" {
		version := params.CustomAgentVersion
		if version == "" {
			version = "latest"
		}
		return fmt.Sprintf("%s:custom_agent:%d:%s@%s", base, params.RepoID, params.CustomAgentName, version)
	}
	return base
}

// buildAgentSubject constructs the subject identity based on whether we use
// the agentic app's identity or the platform identity. The difference is that
// when useAgentIdentity is true, installation_id and AppClientID are used;
// when false, only PlatformClientID is used (ignoring installation ID).
func buildAgentSubject(useAgentIdentity bool, params TokenParams) string {
	if useAgentIdentity && params.AppInstallationID > 0 {
		return fmt.Sprintf("installation_id:%d", params.AppInstallationID)
	}

	ownerType := "org_id"
	if params.OwnerType != sweagentd.OwnerTypeOrganization {
		ownerType = "user_id"
	}

	clientID := params.PlatformClientID
	if useAgentIdentity {
		clientID = params.AppClientID
	}
	if clientID == "" {
		clientID = params.AppClientID
	}
	if clientID == "" {
		clientID = params.PlatformClientID
	}
	return fmt.Sprintf("client_id:%s:owner_id:%s:%d", clientID, ownerType, params.OwnerID)
}
