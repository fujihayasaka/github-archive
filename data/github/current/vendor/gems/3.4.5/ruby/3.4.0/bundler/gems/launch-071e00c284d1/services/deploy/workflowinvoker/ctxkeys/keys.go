package ctxkeys

import "github.com/github/launch/pkg/mu/ctxkey"

var (
	// ExecutingActorIDContextKey is the context key for storing the actor id in context
	ExecutingActorIDContextKey = ctxkey.New("executing_actor_id")
	// OwnerIDContextKey allows us to store the owner id in context
	OwnerIDContextKey = ctxkey.New("owner_id")
	// RepoIDContextKey allows us to store the repo id in context
	RepoIDContextKey = ctxkey.New("repo_id")
)
