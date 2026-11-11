package parser

import (
	"context"
	"testing"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/experiments"
)

func TestProtoConversion(t *testing.T) {
	input := "content:hello world"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_AND,
		Subqueries: []*querypb.Query{
			{
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				Domain:      querypb.Domain_DOMAIN_CONTENT,
				ValueString: "hello",
			},
			{
				Kind: querypb.QueryKind_QUERY_KIND_OR,
				Subqueries: []*querypb.Query{
					{
						Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
						Domain:      querypb.Domain_DOMAIN_PATH,
						ValueString: "world",
					},
					{
						Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
						Domain:      querypb.Domain_DOMAIN_CONTENT,
						ValueString: "world",
					},
					{
						Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
						Domain:      querypb.Domain_DOMAIN_SYMBOLS,
						ValueString: "world",
					},
				},
			},
		},
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionGroups(t *testing.T) {
	input := "(content:hello AND content:world)"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_AND,
		Subqueries: []*querypb.Query{
			{
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				Domain:      querypb.Domain_DOMAIN_CONTENT,
				ValueString: "hello",
			},
			{
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				Domain:      querypb.Domain_DOMAIN_CONTENT,
				ValueString: "world",
			},
		},
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionQualifiers(t *testing.T) {
	input := "path:/xyz/"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind:        querypb.QueryKind_QUERY_KIND_REGEX,
		Domain:      querypb.Domain_DOMAIN_PATH,
		ValueString: "xyz",
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionMoreQualifiers(t *testing.T) {
	input := "repo_id:567 NOT (org_id:234 OR language_id:222)"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_AND,
		Subqueries: []*querypb.Query{
			{
				Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
				Domain:   querypb.Domain_DOMAIN_REPO_ID,
				ValueInt: []int32{567},
			},
			{
				Kind: querypb.QueryKind_QUERY_KIND_NOT,
				Subqueries: []*querypb.Query{
					{
						Kind: querypb.QueryKind_QUERY_KIND_OR,
						Subqueries: []*querypb.Query{
							{
								Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
								Domain:   querypb.Domain_DOMAIN_OWNER_ID,
								ValueInt: []int32{234},
							},
							{
								Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
								Domain:   querypb.Domain_DOMAIN_LANGUAGE_ID,
								ValueInt: []int32{222},
							},
						},
					},
				},
			},
		},
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionTrait(t *testing.T) {
	input := "/def?/ trait:default_branch def:symbol::name"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_AND,
		Subqueries: []*querypb.Query{
			{
				Kind: querypb.QueryKind_QUERY_KIND_OR,
				Subqueries: []*querypb.Query{
					{
						Kind:        querypb.QueryKind_QUERY_KIND_REGEX,
						Domain:      querypb.Domain_DOMAIN_CONTENT,
						ValueString: "def?",
					},
				},
			},
			{
				Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
				Domain:      querypb.Domain_DOMAIN_TRAIT,
				ValueString: "default_branch",
			},
			{
				Kind:        querypb.QueryKind_QUERY_KIND_REGEX,
				Domain:      querypb.Domain_DOMAIN_SYMBOLS,
				ValueString: "(^|\\.|::)symbol::name$",
			},
		},
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionASTScore(t *testing.T) {
	input := "owner_id:123"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	parsed.ASTScore = 10.0

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
		Domain:   querypb.Domain_DOMAIN_OWNER_ID,
		ValueInt: []int32{123},
		AstScore: 10.0,
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionBareRepository(t *testing.T) {
	input := "repo:as[df"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind:   querypb.QueryKind_QUERY_KIND_REGEX,
		Domain: querypb.Domain_DOMAIN_NWO,
		// Special chars in the name should be escaped, and we should be restricted
		// to matching the full repo name
		ValueString: "/as\\[df$",
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionRepositoryRegex(t *testing.T) {
	input := "repo:/as.*df/"
	parsed, err := ParseQuery(context.Background(), input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind:        querypb.QueryKind_QUERY_KIND_REGEX,
		Domain:      querypb.Domain_DOMAIN_NWO,
		ValueString: "as.*df",
	}

	require.Equal(t, expected, proto)
}

func TestProtoConversionPromptQuery(t *testing.T) {
	fakeEmbedding := []float32{0.234, -0.12234, 0.2434, 0.223234}
	input := Embedding(fakeEmbedding, 20)
	proto := ConvertToProto(input)

	expected := &querypb.Query{
		Kind:       querypb.QueryKind_QUERY_KIND_QUALIFIER,
		Domain:     querypb.Domain_DOMAIN_DENSE,
		ValueFloat: fakeEmbedding,
		ValueInt:   []int32{20},
	}
	require.Equal(t, expected, proto)
}

func TestProtoConversionBM25Query(t *testing.T) {
	input := `bm25:"hello world"`
	ctx := experiments.WithExperimentEnabled(context.Background(), experiments.BM25Qualifier)
	parsed, err := ParseQuery(ctx, input)
	require.NoError(t, err)

	proto := ConvertToProto(parsed)

	expected := &querypb.Query{
		Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
		Domain:      querypb.Domain_DOMAIN_BM25,
		ValueString: "hello world",
	}
	require.Equal(t, expected, proto)
}
