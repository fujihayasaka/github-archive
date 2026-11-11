package treelights

import (
	"bytes"
	"context"
	"net/http"
	"strings"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/treelights/proto"
)

type TreelightsClient struct {
	client proto.Highlighter
}

type Client interface {
	HighlightMany(ctx context.Context, req *proto.HighlightRequest) (*proto.HighlightResponse, error)
}

func NewClient(baseURL string, httpClient *http.Client) Client {
	return &TreelightsClient{
		client: proto.NewHighlighterProtobufClient(baseURL, httpClient),
	}
}

type NoopClient struct{}

func NewNoopClient() Client {
	return &NoopClient{}
}

type FakeClient struct {
	results *proto.HighlightResponse
	err     error
}

func NewFakeClient(results *proto.HighlightResponse, err error) Client {
	return &FakeClient{
		results: results,
		err:     err,
	}
}

func (c *FakeClient) HighlightMany(ctx context.Context, req *proto.HighlightRequest) (*proto.HighlightResponse, error) {
	return c.results, c.err
}

func (c *NoopClient) HighlightMany(ctx context.Context, req *proto.HighlightRequest) (*proto.HighlightResponse, error) {
	return &proto.HighlightResponse{}, nil
}

func (c *TreelightsClient) HighlightMany(ctx context.Context, req *proto.HighlightRequest) (*proto.HighlightResponse, error) {
	return c.client.Highlight(ctx, req)
}

const (
	// Use some non-printable characters as special tokens to wrap term matches before sending content to be syntax
	// highlighted. The returned HTML will include these characters, which we can then replace with <mark> tags.
	preMatchTag  = "\u001e\u001f" // to be replaced with: "<mark>"
	openMark     = "<mark>"
	postMatchTag = "\u001f\u001e" // to be replaced with: "</mark>"
	closeMark    = "</mark>"
)

// Create and re-use a strings.Replacer (which is safe for concurrent use).
var replacer = strings.NewReplacer(preMatchTag, openMark, postMatchTag, closeMark)

// Replaces all of the special non-printable characters with HTML <mark> tags.
func ReplaceHighlightTokens(snippet string) string {
	return replacer.Replace(snippet)
}

// Returns the entire content of the document, but with term matches inside snippets wrapped in special non-printable
// characters. Only matches that start inside the snippet will be highlighted. Once syntax highlighting has completed,
// call ReplaceHighlightTokens to replace those markers with HTML <mark> tags.
func AddHighlightTokens(doc *pb.GitDocumentMatch) []byte {
	if len(doc.ScoringInfo.Snippets) == 0 {
		return doc.Content
	}

	termIndex := 0
	content := doc.Content
	termMatches := doc.TermMatches
	buf := bytes.NewBuffer(make([]byte, 0, len(content)+2*len(termMatches)))

	// Write the beginning of the file
	firstSnippetStart := doc.ScoringInfo.Snippets[0].Start
	buf.Write(content[:firstSnippetStart])
	consumed := int(firstSnippetStart)

	// Only do term highlighting in the snippets
	for _, snippet := range doc.ScoringInfo.Snippets {
		// Skip all of the terms from above this snippet
		for termIndex < len(termMatches) && termMatches[termIndex].Start < snippet.Start {
			termIndex++
		}

		// Emit pre and post tags around each term match in the snippet
		for termIndex < len(termMatches) && termMatches[termIndex].Start < snippet.End {
			term := termMatches[termIndex]

			// It's possible that term matches will overlap. Just
			// ignore any overlapping terms.
			if consumed > int(term.Start) {
				termIndex++
				continue
			}

			buf.Write(content[consumed:term.Start])
			buf.WriteString(preMatchTag)
			buf.Write(content[term.Start:term.End])
			buf.WriteString(postMatchTag)

			consumed = int(term.End)
			termIndex++
		}
	}

	// Write the last of the file
	buf.Write(content[consumed:])

	return buf.Bytes()
}
