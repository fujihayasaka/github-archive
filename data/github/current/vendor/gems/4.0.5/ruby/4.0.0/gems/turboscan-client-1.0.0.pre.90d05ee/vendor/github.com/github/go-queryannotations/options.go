package queryannotations

import (
	"context"

	"github.com/github/go-queryannotations/annotation"
)

// Options influencing the behavior

type Option func(context.Context, *Config)

// WithFormatter sets the formatter to use
func WithFormatter(formatter Formatter) Option {
	return func(ctx context.Context, config *Config) {
		config.formatter = formatter
	}
}

// WithPrepend prepends the comment to the query
func WithPrepend() Option {
	return func(ctx context.Context, config *Config) {
		config.prepend = true
	}
}

func WithAnnotations(annotations ...annotation.AnnotationOption) Option {
	return func(ctx context.Context, config *Config) {
		if config.annotations == nil {
			config.annotations = make([]*annotation.Annotation, 0, len(annotations))
		}

		for _, a := range annotations {
			if a == nil {
				continue
			}
			c := a(ctx)
			if c != nil {
				config.annotations = append(config.annotations, c)
			}
		}
	}
}
