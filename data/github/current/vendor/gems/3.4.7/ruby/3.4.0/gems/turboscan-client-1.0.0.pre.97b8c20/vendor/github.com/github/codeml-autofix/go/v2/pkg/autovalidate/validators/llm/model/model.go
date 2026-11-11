// Package model declares LLM model parameter configuration for use in the
// autovalidation system.
package model

// Parameters configures prompt sizing constraints for a model.
type Parameters struct {
	MaxPromptTokens      int
	ReservedPromptTokens int
	CharactersPerToken   int
}

// TODO: Try to remove this, it's probably not needed anymore.

// DefaultParameters are the conservative defaults used when computing prompt sizes.
var DefaultParameters = Parameters{
	// Current CAPI limit
	MaxPromptTokens: 64_000,
	// Reserve prompt tokens for everything other than the source code (e.g. the static sections, the diffs):
	ReservedPromptTokens: 4_000,
	// Assume a conservative number of characters per token:
	CharactersPerToken: 2,
}
