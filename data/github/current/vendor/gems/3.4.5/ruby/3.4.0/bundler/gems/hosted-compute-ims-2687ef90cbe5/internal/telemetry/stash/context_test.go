package stash

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/stretchr/testify/assert"
)

func Test_Context_LoggingFields(t *testing.T) {
	t.Run("add to empty context", func(t *testing.T) {
		newFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}
		expectedFiles := newFields

		ctx := WithLoggingFields(context.Background(), newFields...)
		ctxFields := LoggingFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFiles, ctxFields, "fields should be equal")
	})

	t.Run("duplicate fields", func(t *testing.T) {
		newFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
			kvp.String("key1", "value3"), // duplicate key
			kvp.String("key4", "value4"),
		}
		expectedFields := []kvp.Field{
			kvp.String("key1", "value3"),
			kvp.String("key2", "value2"),
			kvp.String("key4", "value4"),
		}

		ctx := WithLoggingFields(context.Background(), newFields...)
		ctxFields := LoggingFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})

	t.Run("add to non-empty context", func(t *testing.T) {
		ctx := context.Background()
		ctx = WithLoggingFields(ctx, kvp.String("key1", "value1"))
		ctx = WithLoggingFields(ctx, kvp.String("key2", "value2"))
		ctx = WithLoggingFields(ctx, kvp.String("key3", "value3"))

		expectedFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
			kvp.String("key3", "value3"),
		}

		ctxFields := LoggingFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})

	t.Run("context override", func(t *testing.T) {
		ctx := context.Background()
		ctx = WithLoggingFields(ctx, kvp.String("key1", "value1"))
		ctx, cancelFunc := context.WithCancel(ctx)
		defer cancelFunc()
		ctx = context.WithValue(ctx, "noop", "value3") //nolint:staticcheck
		ctx = WithLoggingFields(ctx, kvp.String("key2", "value2"))
		ctx, cancelFunc = context.WithTimeout(ctx, 5*time.Hour)
		defer cancelFunc()

		expectedFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}
		ctxFields := LoggingFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})
}

func Test_Context_StatterFields(t *testing.T) {
	t.Run("add to empty context", func(t *testing.T) {
		newFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}
		expectedFiles := newFields

		ctx := WithStatterFields(context.Background(), newFields...)
		ctxFields := StatterFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFiles, ctxFields, "fields should be equal")
	})

	t.Run("duplicate fields", func(t *testing.T) {
		newFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
			kvp.String("key1", "value3"), // duplicate key
			kvp.String("key4", "value4"),
		}
		expectedFields := []kvp.Field{
			kvp.String("key1", "value3"),
			kvp.String("key2", "value2"),
			kvp.String("key4", "value4"),
		}

		ctx := WithStatterFields(context.Background(), newFields...)
		ctxFields := StatterFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})

	t.Run("add to non-empty context", func(t *testing.T) {
		ctx := context.Background()
		ctx = WithStatterFields(ctx, kvp.String("key1", "value1"))
		ctx = WithStatterFields(ctx, kvp.String("key2", "value2"))
		ctx = WithStatterFields(ctx, kvp.String("key3", "value3"))

		expectedFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
			kvp.String("key3", "value3"),
		}

		ctxFields := StatterFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})

	t.Run("context override", func(t *testing.T) {
		ctx := context.Background()
		ctx = WithStatterFields(ctx, kvp.String("key1", "value1"))
		ctx, cancelFunc := context.WithCancel(ctx)
		defer cancelFunc()
		ctx = context.WithValue(ctx, "noop", "value3") //nolint:staticcheck
		ctx = WithStatterFields(ctx, kvp.String("key2", "value2"))
		ctx, cancelFunc = context.WithTimeout(ctx, 5*time.Hour)
		defer cancelFunc()

		expectedFields := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}
		ctxFields := StatterFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedFields, ctxFields, "fields should be equal")
	})

	t.Run("logger and statter fields together", func(t *testing.T) {
		ctx := context.Background()
		ctx = WithLoggingFields(ctx,
			kvp.String("key1", "value10"),
			kvp.String("key2", "value2"),
		)
		ctx = WithStatterFields(ctx,
			kvp.String("key1", "value20"),
			kvp.String("key3", "value3"),
		)
		ctx = WithLoggingFields(ctx, kvp.String("key4", "value3"))
		ctx = WithStatterFields(ctx, kvp.String("key4", "value4"))

		expectedLoggerFields := []kvp.Field{
			kvp.String("key1", "value10"),
			kvp.String("key2", "value2"),
			kvp.String("key4", "value3"),
		}
		expectedStatterFields := []kvp.Field{
			kvp.String("key1", "value20"),
			kvp.String("key3", "value3"),
			kvp.String("key4", "value4"),
		}

		loggerCtxFields := LoggingFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedLoggerFields, loggerCtxFields, "fields should be equal")

		statterCtxFields := StatterFieldsFromContext(ctx)
		assert.ElementsMatch(t, expectedStatterFields, statterCtxFields, "fields should be equal")
	})
}

func Test_UniqueFields(t *testing.T) {
	t.Run("no duplicates", func(t *testing.T) {
		input := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}
		expectedOutput := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
		}

		assert.ElementsMatch(t, expectedOutput, UniqueFields(input), "fields should be equal")
	})

	t.Run("with duplicates", func(t *testing.T) {
		input := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value2"),
			kvp.String("key3", "value3"),
			kvp.String("key4", "value4"),
			kvp.String("key2", "value7"),
			kvp.String("key3", "value0"),
		}
		expectedOutput := []kvp.Field{
			kvp.String("key1", "value1"),
			kvp.String("key2", "value7"),
			kvp.String("key3", "value0"),
			kvp.String("key4", "value4"),
		}

		assert.ElementsMatch(t, expectedOutput, UniqueFields(input), "fields should be equal")
	})
}
