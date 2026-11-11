package queryannotations

import (
	"context"

	"github.com/github/go-queryannotations/annotation"
)

type ctxKeyType int

var ctxKey ctxKeyType

// WithQueryAnnotations adds the given annotations to the given context.
//
// The given options are immediately evaluated and only the resulting annotations are stored in the context.
func WithQueryAnnotations(ctx context.Context, annotations ...annotation.AnnotationOption) context.Context {
	qa := getAnnotations(ctx)

	if qa == nil {
		qa = make([]*annotation.Annotation, 0, len(annotations))
	} else {
		// Clone
		qaClone := make([]*annotation.Annotation, len(qa), len(qa)+len(annotations))
		copy(qaClone, qa)
		qa = qaClone
	}

	for _, opt := range annotations {
		qa = append(qa, opt(ctx))
	}

	return context.WithValue(ctx, ctxKey, qa)
}

func getAnnotations(ctx context.Context) []*annotation.Annotation {
	if v := ctx.Value(ctxKey); v != nil {
		return v.([]*annotation.Annotation)
	}

	return nil
}
