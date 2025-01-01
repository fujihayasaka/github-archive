// Package pipeline implements post-processing of email content.
package pipeline

import (
	"context"

	"github.com/tdewolff/minify/v2"
	minifyhtml "github.com/tdewolff/minify/v2/html"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// PostProcessor represents a post processor.
type PostProcessor interface {
	// Process is used for post processing emails step. Monolith already supports this so for MVP we decided
	// to rely on monolith twirp endpoint instead of creating and managing new service.
	Process(ctx context.Context, tenant tenancy.Tenant, rawHTML string) (string, error)
}

// Minifier represents a Minify HTML postprocessor
type Minifier struct {
	minifier *minify.M
}

// NewMinifier creates a new Minifier postprocessor.
func NewMinifier() PostProcessor {
	m := minify.New()
	m.Add("text/html", &minifyhtml.Minifier{
		KeepConditionalComments: true,
		KeepDefaultAttrVals:     true,
		KeepDocumentTags:        true,
		KeepEndTags:             true,
		KeepQuotes:              true,

		// Just remove whitespaces
		KeepWhitespace: false,
	})

	return &Minifier{minifier: m}
}

// Process minifies the html content.
func (m *Minifier) Process(ctx context.Context, _ tenancy.Tenant, html string) (string, error) {
	minified, err := m.minifier.String("text/html", html)
	if err != nil {
		return "", errors.Wrap(err, "pipeline: error trying to minify html")
	}

	return minified, nil
}
