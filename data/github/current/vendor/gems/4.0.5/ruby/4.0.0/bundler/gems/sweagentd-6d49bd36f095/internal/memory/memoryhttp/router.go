package memoryhttp

// This file centralises HTTP route registration for memory operations.
//
// Repo-scoped routes (except /enabled, which queries the chain and returns
// JSON) are wrapped by withRepoMemoryCheck, which enforces the full memory
// enablement chain for the repo:
//
//	Policy via Monolith Twirp -> repo/owner feature flag -> repo admin setting
//
// User-scoped routes (except /memory/v0/user/enabled) are wrapped by
// withUserMemoryCheck, which enforces the user-affecting layers only:
//
//	Policy via Monolith Twirp -> user feature flags
//
// Per the memory opt-out matrix agreed in github/agents#945, the repo
// admin's repo_memory_disabled setting affects only repo memories; user
// memories follow the user across repos by design and are gated only by
// the user-affecting layers. Centralising registration here keeps
// enforcement uniform across every endpoint and avoids duplicating
// auth/enablement logic in handlers.

import (
	"github.com/go-chi/chi/v5"
)

// RegisterAllMemoryRoutes registers every memory route (repo-scoped,
// user-scoped, and the combined prompt route) on the supplied chi router.
//
// Repo-scoped routes are placed behind withRepoMemoryCheck so that disabled
// repos return 404 ErrFeatureNotEnabled before any handler-specific work
// runs. User-scoped routes are placed behind withUserMemoryCheck so that
// disabled users hit the same fast-fail. The two /enabled endpoints are
// intentionally NOT wrapped: clients query them to learn the chain result
// and expect a 200 response with {"enabled": false} rather than a 404.
func (h *MemoryHandler) RegisterAllMemoryRoutes(r chi.Router) {
	h.RegisterRepoRoutes(r)
	h.RegisterUserRoutes(r)
	h.RegisterCombinedRoutes(r)
}

// RegisterRepoRoutes registers the HTTP routes for repo-scoped memory operations.
//
// The /enabled endpoint runs without withRepoMemoryCheck because clients query
// it to learn the chain result; everything else is gated by the full repo
// enablement chain (Policy -> repo/owner FF -> repo admin setting) via the
// withRepoMemoryCheck middleware.
func (h *MemoryHandler) RegisterRepoRoutes(r chi.Router) {
	r.Route("/memory/v0/{owner}/{repo}", func(r chi.Router) {
		r.Use(h.withMemoryRequest())
		r.Use(h.withIntegrationKillSwitch())

		// /enabled returns the chain result as JSON; do not gate it.
		r.Get("/enabled", h.HandleCheckMemoryEnabled)

		// Read endpoints — require pull access on the repo.
		r.Group(func(r chi.Router) {
			r.Use(h.withRepoMemoryCheck(readPermission))

			r.Get("/recent", h.HandleGetRecentMemories)
			r.Get("/top", h.HandleGetTopMemories)
			r.Get("/prompt", h.HandleGetPrompt)
		})

		// Write endpoints — require push access on the repo.
		r.Group(func(r chi.Router) {
			r.Use(h.withRepoMemoryCheck(writePermission))

			r.Put("/", h.HandleCreateMemory)
			r.Delete("/{memoryId}", h.HandleDeleteMemory)
			r.Delete("/", h.HandleDeleteAllMemories)
			r.Post("/delete", h.HandleDeleteMemories)
			r.Post("/vote", h.HandleVoteMemory)
		})
	})
}

// RegisterUserRoutes registers the HTTP routes for user-scoped memory operations.
//
// Per the memory opt-out matrix (github/agents#945), user-scope routes are
// intentionally NOT gated by the repo-admin opt-out: user memories follow
// the user across repos by design and ignore per-repo admin settings. They
// ARE gated by user-affecting layers (Policy, user FFs, integration FFs)
// via withUserMemoryCheck.
//
// We accept the residual cross-repo data-leak risk where a user memory
// captured in an opted-out repo could later surface elsewhere. That risk is
// addressed by prompt hardening and admin messaging, not by suppressing
// user memories.
//
// /memory/v0/user/enabled is intentionally not behind withUserMemoryCheck:
// clients query it to learn the chain result and expect a 200 with
// {"enabled": false} rather than a 404. The handler consults the same chain
// internally so the answer remains consistent.
func (h *MemoryHandler) RegisterUserRoutes(r chi.Router) {
	r.Route("/memory/v0/user", func(r chi.Router) {
		r.Use(h.withMemoryRequest())
		r.Use(h.withIntegrationKillSwitch())

		// /enabled returns the chain result as JSON; do not gate it.
		r.Get("/enabled", h.HandleCheckUserMemoryEnabled)

		r.Group(func(r chi.Router) {
			r.Use(h.withUserMemoryCheck())

			r.Put("/", h.HandleCreateUserMemory)
			r.Get("/recent", h.HandleGetRecentUserMemories)
			r.Get("/top", h.HandleGetTopUserMemories)
			r.Delete("/{memoryId}", h.HandleDeleteUserMemory)
			r.Delete("/", h.HandleDeleteAllUserMemories)
			r.Post("/delete", h.HandleDeleteUserMemories)
			r.Post("/vote", h.HandleVoteUserMemory)
		})
	})
}

// RegisterCombinedRoutes registers the HTTP route for the combined prompt
// endpoint, which returns both repo-scoped (when ?repo= is present) and
// user-scoped memories in a single response.
//
// This route is intentionally not behind withRepoMemoryCheck or
// withUserMemoryCheck because the repo parameter is optional and the two
// scopes are gated asymmetrically per the memory opt-out matrix
// (github/agents#945). When ?repo= is present, the handler authorises the
// repo and runs a two-step enablement check inline:
//
//  1. User-affecting layers (Policy + repo/owner FF + featureDisallowed)
//     gate BOTH scopes. If disabled, the handler drops repo AND user
//     memories.
//  2. Repo-admin opt-out (repo_memory_disabled) gates ONLY repo memories.
//     If disabled, the handler drops only the repo scope and continues to
//     return user memories.
//
// Step 2 is fail-closed at this data-flow injection point: a transient
// Dotcom Twirp blip drops the repo scope rather than silently surfacing
// repo memories from a possibly opted-out repo.
func (h *MemoryHandler) RegisterCombinedRoutes(r chi.Router) {
	r.Route("/memory/v0", func(r chi.Router) {
		r.Use(h.withMemoryRequest())
		r.Use(h.withIntegrationKillSwitch())

		r.Get("/prompt", h.HandleGetCombinedPrompt)
	})
}
