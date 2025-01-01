package queryannotations

import (
	"context"
	"strings"

	"github.com/github/go-queryannotations/annotation"
)

func Annotate(ctx context.Context, query string, opts ...Option) string {
	return queryWithComment(ctx, query, opts...)
}

func queryWithComment(ctx context.Context, query string, opts ...Option) string {
	config := evaluateOptions(ctx, opts...)

	capacity := len(config.annotations)

	additionalAnnotations := getAnnotations(ctx)
	capacity += len(additionalAnnotations)

	components := make([]*annotation.Annotation, len(config.annotations), capacity)
	copy(components, config.annotations)

	// Add components from context
	for _, c := range additionalAnnotations {
		if c != nil {
			components = append(components, c)
		}
	}

	if len(components) == 0 {
		return query
	}

	sb := &strings.Builder{}

	// Reserve space for
	// - comment
	// - query
	// - whitespace before/after query/comment
	sb.Grow(len(query) + 2 + commentBufferSize(components, config))

	if !config.prepend {
		sb.WriteString(query)
		sb.WriteString(" ")
	}

	genComment(sb, components, config)

	if config.prepend {
		if sb.Len() > 0 {
			sb.WriteString(" ")
		}
		sb.WriteString(query)
	}

	return sb.String()
}
