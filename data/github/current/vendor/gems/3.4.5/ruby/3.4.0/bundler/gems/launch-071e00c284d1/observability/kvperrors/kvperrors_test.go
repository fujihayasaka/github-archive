package kvperrors

import (
	"testing"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
)

func Test_FindContext(t *testing.T) {
	f := kvp.String("some-key", "some-val")
	kvpF := kvp.String("some-key", "some-val")

	simpleErr := errors.New("simple error with no context")
	assert.Nil(t, FindContext(simpleErr))

	ctxErr := With("error message with context", kvpF)
	assert.Equal(t, []kvp.Field{f}, FindContext(ctxErr))

	wrappedErr := errors.Wrap(ctxErr, "wrapper1")
	assert.Equal(t, []kvp.Field{f}, FindContext(wrappedErr))

	doubleWrappedErr := errors.Wrap(wrappedErr, "wrapper2")
	assert.Equal(t, []kvp.Field{f}, FindContext(doubleWrappedErr))

	contextDecoratedErr := WrapWith(simpleErr, kvpF)
	assert.Equal(t, []kvp.Field{f}, FindContext(contextDecoratedErr))
}
