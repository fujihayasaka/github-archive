package parser

import (
	"context"
	"fmt"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-reqmeta"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/embeddings"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
)

func GetPromptRewriter(ctx context.Context, copilot copilot.Client, corpus routing.Corpus) PromptRewriter {
	if value, ok := experiments.GetExperiment(ctx, experiments.PromptQualifier); ok {
		switch value {
		case experiments.Enabled:
			model, dimensions := corpus.DefaultEmbeddingModel()
			return NewEmbeddingsRewriter(copilot, model, dimensions)
		case experiments.PromptQualifierBM25:
			return BM25PromptRewriter{}
		}
	}

	return DisallowPromptQueries{}
}

// PromptRewriter defines how to rewrite any `prompt` qualifiers that appear in
// a query.
type PromptRewriter interface {
	// RewritePrompt rewrites a `prompt` qualifier.  The `query` is guaranteed
	// to be a `prompt` qualifier, whose `Value` is the text of the prompt.  You
	// should replace the contents of `query` with the rewritten prompt, and
	// return a cost that will be added to the query preparation cost of the
	// query.
	RewritePrompt(
		ctx context.Context,
		query *Query,
		actor *models.Actor,
	) error

	// ValidateRepo ensures that any repos mentioned in a search query have all
	// of the data needed to satisfy any rewritten `prompt` qualifiers.  `query`
	// will be an AST node representing a `repo` qualifier, and `repo` will be
	// the snapshot entry for that repository.
	ValidateRepo(
		ctx context.Context,
		query *Query,
		repo *snapshotpb.SnapshotEntry,
	) *QueryError

	// Cost returns the query preparation cost for rewriting a particular number
	// of `prompt` qualifiers.
	Cost(embeddingCount int) float32

	// OverrideSnippetMode allows the prompt rewriter to choose a different snippet mode
	// than what is requested by the user.
	//
	// TODO This should eventually be replaced by fixing the broken snippeting modes.
	OverrideSnippetMode(mode pb.SnippetMode) pb.SnippetMode
}

// DisallowPromptQueries is a [PromptRewriter] that rewrites every `prompt`
// qualifier into a simple text query.
type DisallowPromptQueries struct{}

func (_ DisallowPromptQueries) RewritePrompt(
	ctx context.Context,
	query *Query,
	actor *models.Actor,
) error {
	original := *query
	rewritten := Text(query.Value)
	rewritten.OriginalQuery = &original
	*query = *rewritten
	return nil
}

func (_ DisallowPromptQueries) ValidateRepo(
	ctx context.Context,
	query *Query,
	repo *snapshotpb.SnapshotEntry,
) *QueryError {
	return nil
}

func (_ DisallowPromptQueries) Cost(embeddingCount int) float32 {
	return 0
}

func (_ DisallowPromptQueries) OverrideSnippetMode(mode pb.SnippetMode) pb.SnippetMode {
	return mode
}

// EmbeddingsRewriter is a [PromptRewriter] that translates each prompt into an
// embedding, by calling out to an embedding API.
type EmbeddingsRewriter struct {
	copilot    copilot.Client
	model      string
	dimensions int
}

func NewEmbeddingsRewriter(
	copilot copilot.Client,
	model string,
	dimensions int,
) *EmbeddingsRewriter {
	return &EmbeddingsRewriter{
		copilot:    copilot,
		model:      model,
		dimensions: dimensions,
	}
}

func (er *EmbeddingsRewriter) withCachedEmbedding(
	ctx context.Context,
	prompt string,
	userID uint32,
) ([]float32, error) {
	isTestQuery := false
	if prompt == "text" && er.model == routing.Text3SmallInference {
		isTestQuery = true
	}

	// Temporary: `text` prompt queries from vscode are just checking to see if a repo is in the semantic index or not. We
	// hardcode the embeddings computation and add a flag to our logs and stats so that we don't pollute our metrics. (NB:
	// modify the global request metadata so the Twirp hooks can use it).
	//
	// NOTE: This modifies the tags on the RequestMetadata, not a copy. This should be thread safe because every request
	// has its own context.
	if rmeta, ok := reqmeta.GetRequestMetadata(ctx); ok {
		rmeta.TagStatsWith(stats.Tags{"test_query": fmt.Sprintf("%t", isTestQuery)})
		rmeta.LogWith(kvp.Bool("test_query", isTestQuery))
	}

	if isTestQuery {
		statting.Counter(ctx, "fetch.hard_coded_embedding", 1)
		return embeddings.TextEmbedding3SmallText, nil
	}

	return er.copilot.GetEmbedding(ctx, prompt, userID, er.model, er.dimensions)
}

func (er *EmbeddingsRewriter) RewritePrompt(
	ctx context.Context,
	query *Query,
	actor *models.Actor,
) error {
	var userID uint32
	if actor != nil {
		userID = actor.ID
	}

	embedding, err := er.withCachedEmbedding(ctx, query.Value, userID)
	if err != nil {
		logging.Error(ctx, "failed to get embedding", kvp.Err(err))
		statting.Counter(ctx, "fetch.embedding.error", 1)
		return err
	}

	original := *query
	angle := original.IntValues[0]
	if angle == UnspecifiedAngle {
		angle = 70
	}

	embeddingQuery := Embedding(embedding, angle)
	embeddingQuery.DivorToRetrieve = constants.PromptDivorToRetrieve
	embeddingQuery.DivorToScore = constants.PromptDivorToScore
	embeddingQuery.OriginalQuery = &original
	embeddingQuery.Start = original.Start
	embeddingQuery.End = original.End

	*query = *embeddingQuery
	return nil
}

func (er *EmbeddingsRewriter) ValidateRepo(
	ctx context.Context,
	query *Query,
	repo *snapshotpb.SnapshotEntry,
) *QueryError {
	_, hasCode := repo.Experiments[experiments.EnableCodeEmbedding]
	if hasCode {
		return nil
	}

	errType := ErrorTypeCodeEmbeddingsUnavailable

	_, hasDocs := repo.Experiments[experiments.EnableDocsEmbedding]
	if !hasDocs {
		errType = ErrorTypeDocsEmbeddingsUnavailable
	}

	return &QueryError{
		Message:                fmt.Sprintf("Embeddings unavailable for %s", repo.Nwo),
		Ranges:                 []Range{{query.Start, query.End}},
		Type:                   errType,
		InaccessibleRepoOrgNWO: repo.Nwo,
	}
}

func (er *EmbeddingsRewriter) Cost(embeddingCount int) float32 {
	return float32(float64(embeddingCount) * quota.CAPIEmbeddingsCharge)
}

func (_ *EmbeddingsRewriter) OverrideSnippetMode(mode pb.SnippetMode) pb.SnippetMode {
	return mode
}

// BM25PromptRewriter is a [PromptRewriter] that rewrites every `prompt`
// qualifier into a BM25 search.
type BM25PromptRewriter struct{}

func (_ BM25PromptRewriter) RewritePrompt(
	ctx context.Context,
	query *Query,
	actor *models.Actor,
) error {
	original := *query
	rewritten := BM25(original.Value)
	rewritten.Start = original.Start
	rewritten.End = original.End
	*query = *rewritten
	return nil
}

func (_ BM25PromptRewriter) ValidateRepo(
	ctx context.Context,
	query *Query,
	repo *snapshotpb.SnapshotEntry,
) *QueryError {
	return nil
}

func (_ BM25PromptRewriter) Cost(embeddingCount int) float32 {
	return 0
}

func (_ BM25PromptRewriter) OverrideSnippetMode(mode pb.SnippetMode) pb.SnippetMode {
	if mode == pb.SnippetMode_SNIPPET_MODE_RAW_MATCHES {
		return pb.SnippetMode_SNIPPET_MODE_LLM
	}
	return mode
}
