package stash

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
)

type (
	ctxLoggingFieldsKeyType struct{}
	ctxStatterFieldsKeyType struct{}
)

var (
	ctxLoggingFieldsKey ctxLoggingFieldsKeyType
	ctxStatterFieldsKey ctxStatterFieldsKeyType
)

func LoggingFieldsFromContext(ctx context.Context) []kvp.Field {
	fields, ok := ctx.Value(ctxLoggingFieldsKey).([]kvp.Field)
	if !ok {
		return []kvp.Field{}
	}

	return fields
}

func WithLoggingFields(ctx context.Context, newFields ...kvp.Field) context.Context {
	oldFields := LoggingFieldsFromContext(ctx)
	updatedFields := UniqueFields(append(oldFields, newFields...))

	return context.WithValue(ctx, ctxLoggingFieldsKey, updatedFields)
}

func StatterFieldsFromContext(ctx context.Context) []kvp.Field {
	fields, ok := ctx.Value(ctxStatterFieldsKey).([]kvp.Field)
	if !ok {
		return []kvp.Field{}
	}

	return fields
}

func WithStatterFields(ctx context.Context, newFields ...kvp.Field) context.Context {
	oldFields := StatterFieldsFromContext(ctx)
	updatedFields := UniqueFields(append(oldFields, newFields...))

	return context.WithValue(ctx, ctxStatterFieldsKey, updatedFields)
}

func UniqueFields(fields []kvp.Field) []kvp.Field {
	// latest wins
	uniqueFields := map[string]kvp.Field{}
	for _, field := range fields {
		uniqueFields[field.Key] = field
	}

	result := make([]kvp.Field, 0, len(uniqueFields))
	for _, field := range uniqueFields {
		result = append(result, field)
	}

	return result
}
