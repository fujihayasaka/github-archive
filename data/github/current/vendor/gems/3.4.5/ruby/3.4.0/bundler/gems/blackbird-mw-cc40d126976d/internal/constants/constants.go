package constants

import (
	"math"
	"time"
)

// Application level constants that don't belong in configuration.
const (
	// GetBlobsFetchConcurrency is the number of concurrent spokesd calls to fetch
	// blob content.
	GetBlobsFetchConcurrency = 10

	// GetBlobsBatchSize is the number of blobs to fetch from spokesd in a single
	// HTTP call.
	GetBlobsBatchSize = 25

	// SpokesHTTPRetries is the number of times to retry failed HTTP requests to Spokes API
	// (used with an exponential backoff).
	SpokesHTTPRetries = 3

	// UserACLCacheTTL is the TTL of the redis cache of user accessible repositories.
	UserACLCacheTTL = 10 * time.Minute

	// Max length in bytes
	MaxQueryLengthInBytes int = 1000

	// Org ID for GitHub (for detecting staff members)
	GitHubOrgID = 9919

	// The largest trailing zeros trait
	MaxTrailingZeros = 30

	// Settings for result count estimation
	CountExactDivorToScore       = 5
	CountApproximateDivorToScore = 4
	CountDivorToRetrieve         = 1000

	// Settings for syntax highlighting
	SyntaxHighlightingMaxFilesize    = 100 * 1024
	SyntaxHighlightingMaxFilesizeCPP = 50 * 1024 // about 2000 lines of C/C++

	// Settings for prompt/embedding queries
	PromptDivorToRetrieve = uint32(1_00_000)
	PromptDivorToScore    = uint32(1_00_000)
)

// If linguist cannot detect language we use u32 max to represent this.
const UnknownLanguageId uint32 = math.MaxUint32
const CPPLanguageId uint32 = 43
const CLanguageID uint32 = 41
