package experiments

import (
	"context"
	"database/sql/driver"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/github/go-stats"
	"github.com/github/go-telemetry/statting"
)

type ctxKeyValueExperiments struct{}

type Experiments map[string]string

func (e *Experiments) String() string {
	raw, err := e.serialize()
	if err != nil {
		panic(fmt.Sprintf("failed to serialize experiments: %v", err))
	}
	return raw
}

// Scan implements the Scanner interface.
func (e *Experiments) Scan(value any) error {
	switch s := value.(type) {
	case nil:
		*e = nil
		return nil
	case string:
		*e = deserialize(s)
		return nil
	case []byte:
		*e = deserialize(string(s))
		return nil
	default:
		return fmt.Errorf("unsupported scan type %T: %+v", value, value)
	}
}

// Value implements the driver Valuer interface.
func (e Experiments) Value() (driver.Value, error) {
	if e == nil {
		return nil, nil
	}
	return e.serialize()
}

func (e Experiments) Equal(other Experiments) bool {
	if len(e) != len(other) {
		return false
	}

	if len(e) == 0 && len(other) == 0 {
		return true
	}

	eser, err := e.serialize()
	if err != nil {
		return false
	}

	oser, err := other.serialize()
	if err != nil {
		return false
	}

	return eser == oser
}

var invalidKeyOrValueRegex = regexp.MustCompile(`[=,]`)

func (e Experiments) serialize() (string, error) {
	parts := []string{}
	for k, v := range e {
		if invalidKeyOrValueRegex.MatchString(k) {
			return "", fmt.Errorf("invalid experiment key: %q", k)
		}
		if invalidKeyOrValueRegex.MatchString(v) {
			return "", fmt.Errorf("invalid experiment value: %q", v)
		}
		parts = append(parts, fmt.Sprintf("%s=%s", k, v))
	}
	// NB: Sort so that serialized representations are directly comparable.
	sort.Slice(parts, func(i, j int) bool { return parts[i] < parts[j] })
	raw := strings.Join(parts, ",")
	if len(raw) > 512 {
		// NB: This was the size of the db column in the schemas/blackbird_snapshot_entries.sql table.
		return "", fmt.Errorf("serialized experiments exceeds max length of 512 bytes: len=%d", len(raw))
	}
	return raw, nil
}

func deserialize(raw string) Experiments {
	experiments := Experiments{}
	for _, part := range strings.Split(raw, ",") {
		kv := strings.Split(part, "=")
		if len(kv) == 2 && kv[0] != "" {
			experiments[kv[0]] = kv[1]
		}
	}
	return experiments
}

// Merge (overriding) the experiments into the context.
func WithExperiments(ctx context.Context, experiments Experiments) context.Context {
	val := GetExperiments(ctx)
	for k, v := range experiments {
		val[k] = v
	}
	return withExperiments(ctx, val)
}

// Replaces the experiments in the context with.
func withExperiments(ctx context.Context, val Experiments) context.Context {
	for k, v := range val {
		statting.Counter(ctx, "experiments.set", 1, stats.Tags{"experiment_key": k, "experiment_value": v})
	}
	return context.WithValue(ctx, ctxKeyValueExperiments{}, val)
}

// Merge (overriding) the given keys as simple boolean experiments into the context.
func WithExperimentsEnabled(ctx context.Context, keys []string) context.Context {
	val := GetExperiments(ctx)
	for _, key := range keys {
		val[key] = Enabled
	}
	return withExperiments(ctx, val)
}

// Merge (overriding) the key as an experiment into the context.
func WithExperiment(ctx context.Context, key string, value string) context.Context {
	val := GetExperiments(ctx)
	val[key] = value
	return withExperiments(ctx, val)
}

// Merge (overriding) the key as a simple boolean experiment into the context.
func WithExperimentEnabled(ctx context.Context, key string) context.Context {
	return WithExperiment(ctx, key, Enabled)
}

// Check if an experiment is enabled.
func IsExperimentEnabled(ctx context.Context, key string) bool {
	val := GetExperiments(ctx)
	v, ok := val[key]
	return ok && v != Disabled
}

// Get the value of an experiment.
func GetExperiment(ctx context.Context, key string) (string, bool) {
	val := GetExperiments(ctx)
	v, ok := val[key]
	return v, ok
}

// Get all experiments from the context.
func GetExperiments(ctx context.Context) Experiments {
	if val, ok := ctx.Value(ctxKeyValueExperiments{}).(Experiments); ok {
		return val
	}
	return Experiments{}
}

// List of experiments enabled by default for for github staff.
var StaffEnabled = Experiments{}

// Canonical list of valid experiments. Many of these can be set manually (by staff) in the front end experiments dialog
// from the search results page. Other experiments are set by clients of blackbird-mw to toggle features and control
// behavior. For example, backing the legacy search API requires setting the `pagination` and
// `use_geyser_query_language` experiments.
const (
	// Canonical enabled value for experiments. Only the existence of the key is
	// required, but this is the convention to easily support setting experiments
	// via url params.
	Enabled = "1"

	// To explicitly disable an experiment, set it to zero.
	Disabled = "0"

	// Set zero_quota=1 to force the rate limiter to reject the query as if your quota was exhausted.
	ZeroQuota = "zero_quota"

	// Force corpus selection (e.g., corpus=blue).
	ForceCorpus = "corpus"

	// Control the snippet mode (e.g., snippet_mode=unified). Dotcom sets
	// snippet_mode=auto for all requests.
	SnippetMode            = "snippet_mode"
	SnippetModeAuto        = "auto"
	SnippetModeHighDensity = "high_density"
	SnippetModeUnified     = "unified"
	SnippetModeRaw         = "raw"
	SnippetModeLLM         = "llm"

	// Enable detailed logging of snippet highlighting (e.g., snippet_highlight_logging=1).
	SnippetHighlightLogging = "snippet_highlight_logging"

	// Disable crowding (e.g. no_crowding=1). Crowding is enabled by default.
	NoCrowding = "no_crowding" // Deprecated, todo: remove

	// Force use of geyser query language in blackbird (e.g., // use_geyser_query_language=1). By
	// default, the geyser parser is used to back the legacy API, but you can set this experiment to
	// force using the legacy query language for normal web queries.
	UseGeyserQueryLanguage = "use_geyser_query_language"

	// Use pagination (e.g., pagination=1). Dotcom sets this to support the legacy api queries.
	Pagination = "pagination"

	// Enables the new prompt qualifier in queries (e.g., prompt_qualifier=1 or prompt_qualifier=bm25), optionally
	// selecting which particular model to handle the prompt text.
	PromptQualifier     = "prompt_qualifier"
	PromptQualifierBM25 = "bm25" // Deprecated, todo: remove after September 2024

	// Queries won't be logged when this experiment is enabled.
	DisableQueryLogging = "disable_query_logging"

	// Enables the new ref qualifier in queries (e.g. ref_qualifiers=1).
	RefQualifier = "ref_qualifier"

	// Provide more debug scoring info in the response
	ExtendedScoringInfo = "extended_scoring_info"

	// Overrides the snippet max length in SnippetInfo
	SnippetSize = "snippet_size"

	// Enables the BM25 qualifier
	BM25Qualifier = "bm25_qualifier"

	// Enable all semantic search query lint validation, including those that we
	// are still measuring the impact of.
	AllSemanticSearchLints = "all_semantic_search_lints"
)

// Repo experiments are set on individual repos during ingest and persisted in the snapshot indices.
//
// NOTE: these don't work via the UI!
const (
	// Index embeddings for code in this repo in hybrid clusters.
	EnableCodeEmbedding = "blackbird_enable_code_embedding"
	// Index embeddings for docs in this repo in hybrid clusters.
	EnableDocsEmbedding = "blackbird_enable_markdown_embedding"
)
