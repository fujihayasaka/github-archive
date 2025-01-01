// Package model declares LLM model parameter configuration for use in the
// autovalidation system.
package model

// ModelParameters configures prompt sizing constraints for a model.
type ModelParameters struct {
	MaxPromptTokens      int
	ReservedPromptTokens int
	CharactersPerToken   int
}

// TODO: Try to remove this, it's probably not needed anymore.

// DefaultModelParameters are the conservative defaults used when computing prompt sizes.
var DefaultModelParameters = ModelParameters{
	// Current CAPI limit
	MaxPromptTokens: 64_000,
	// Reserve prompt tokens for everything other than the source code (e.g. the static sections, the diffs):
	ReservedPromptTokens: 4_000,
	// Assume a conservative number of characters per token:
	CharactersPerToken: 2,
}
