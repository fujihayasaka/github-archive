package queryannotations

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/go-queryannotations/annotation"
)

type Formatter interface {
	Name() string

	Estimate(components []*annotation.Annotation) int
	WriteComponent(sb *strings.Builder, c *annotation.Annotation)

	ParseComponent(comment string) (*annotation.Annotation, error)
}

type Config struct {
	annotations []*annotation.Annotation

	formatter Formatter

	// defaults to `,`
	separator string

	prepend bool
}

var (
	defaultOptions = Config{
		separator: ",",
		formatter: &MarginaliaFormatter{},
	}
)

// GenerateComment generates a comment string from the given components.
func GenerateComment(ctx context.Context, opts ...Option) string {
	if len(opts) == 0 {
		return ""
	}

	options := defaultOptions
	for _, o := range opts {
		o(ctx, &options)
	}

	// Filter out nil components
	comps := make([]*annotation.Annotation, 0, len(options.annotations))
	for _, c := range options.annotations {
		if c != nil {
			comps = append(comps, c)
		}
	}

	if len(comps) == 0 {
		return ""
	}

	sb := &strings.Builder{}
	sb.Grow(commentBufferSize(comps, options))

	genComment(sb, comps, options)

	return sb.String()
}

func commentBufferSize(components []*annotation.Annotation, options Config) int {
	var size int
	size = size + 2*3                                    // "/* " and " */" comment delimiters
	size = size + options.formatter.Estimate(components) // components
	size = size + len(components)*len(options.separator) // separators between components
	return size
}

func genComment(sb *strings.Builder, components []*annotation.Annotation, options Config) {
	sbc := &strings.Builder{}
	sbc.Grow(commentBufferSize(components, options)) // this overestimates by a few characters, but it's only an approximation in any case

	for i, c := range components {
		if i > 0 {
			sbc.WriteString(options.separator)
		}

		options.formatter.WriteComponent(sbc, c)
	}

	comment := sbc.String()

	escapedComment := escapeComment(comment)

	sb.WriteString("/*")
	sb.WriteString(escapedComment)
	sb.WriteString("*/")
}

// ParseQueryWithComment parses the given text and returns the query string, all comments in the query text, and any parsed components.
func ParseQueryWithComment(ctx context.Context, text string, opts ...Option) (string, []string, []*annotation.Annotation, error) {
	options := evaluateOptions(ctx, opts...)

	// Parse comments
	var comments []string
	builder := strings.Builder{}

	cStart := strings.Index(text, "/*")
	if cStart == -1 || cStart == len(text) {
		return text, nil, nil, nil
	}

	for len(text) > 0 {
		builder.WriteString(text[:cStart])
		text = text[cStart+2:]
		cEnd := strings.Index(text, "*/")
		if cEnd >= 0 && cEnd < len(text) {
			comments = append(comments, strings.TrimSpace(text[:cEnd]))
			text = text[cEnd+2:]
		} else {
			comments = append(comments, strings.TrimSpace(text[:]))
			break
		}

		cStart = strings.Index(text, "/*")
		if cStart == -1 || cStart == len(text) {
			// if we are breaking out of the loop, make sure we copy
			// the remaining text buffer to the builder
			builder.WriteString(text)
			break
		}
	}

	// Split comments into components
	components := make([]*annotation.Annotation, 0)

	for _, c := range comments {
		segments := strings.Split(c, options.separator)
		for _, segment := range segments {
			if segment == "" {
				continue
			}

			component, err := options.formatter.ParseComponent(segment)
			if err != nil {
				return "", nil, nil, fmt.Errorf("parsing component: %w", err)
			}

			if component != nil {
				components = append(components, component)
			}
		}
	}

	return strings.TrimSpace(builder.String()), comments, components, nil
}

func evaluateOptions(ctx context.Context, opts ...Option) Config {
	options := defaultOptions

	for _, o := range opts {
		o(ctx, &options)
	}

	return options
}

func escapeComment(comment string) string {
	// Rails also removes leading `/*` and `*/` from comments	via this regex:
	// %r{\A\s*/\*\+?\s?|\s?\*/\s*\Z}
	// See: https://github.com/rails/rails/blob/19eebf6d33dd15a0172e3ed2481bec57a89a2404/activerecord/lib/active_record/query_logs.rb#L136-L147
	// Here we're only relying on adding spaces to break up `/*` and `*/` sequences.
	comment = strings.ReplaceAll(comment, "*/", "* /")
	comment = strings.ReplaceAll(comment, "/*", "/ *")

	return comment
}
