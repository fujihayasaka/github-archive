package model

type ModelParameters struct {
	MaxPromptTokens      int
	ReservedPromptTokens int
	CharactersPerToken   int
}

var DefaultModelParameters = ModelParameters{
	// Current CAPI limit
	MaxPromptTokens: 64_000,
	// Reserve prompt tokens for everything other than the source code (e.g. the static sections, the diffs):
	ReservedPromptTokens: 4_000,
	// Assume a conservative number of characters per token:
	CharactersPerToken: 2,
}
