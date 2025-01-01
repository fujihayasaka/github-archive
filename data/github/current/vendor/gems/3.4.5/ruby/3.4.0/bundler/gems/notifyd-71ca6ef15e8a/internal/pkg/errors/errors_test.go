package errors

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_RetriableErrors(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name      string
		fn        func() error
		msg       string
		retriable bool
		transient bool
		panic     bool
		errorType string
	}{
		{
			name:      "New normal error",
			fn:        func() error { return New("oops") },
			msg:       "oops",
			retriable: false,
			transient: false,
			panic:     false,
			errorType: "normal",
		},
		{
			name:      "New retriable error",
			fn:        func() error { return New("oops").With(MarkRetriable()) },
			msg:       "oops",
			retriable: true,
			transient: true,
			panic:     false,
			errorType: "retriable",
		},
		{
			name:      "Newf normal error",
			fn:        func() error { return Newf("oops %d", 1) },
			msg:       "oops 1",
			retriable: false,
			transient: false,
			panic:     false,
			errorType: "normal",
		},
		{
			name:      "Newf retriable error",
			fn:        func() error { return Newf("oops %d", 1).With(MarkRetriable()) },
			msg:       "oops 1",
			retriable: true,
			transient: true,
			panic:     false,
			errorType: "retriable",
		},
		{
			name:      "Wrap normal error",
			fn:        func() error { return Wrap(fmt.Errorf("oops"), "extra") },
			msg:       "extra: oops",
			retriable: false,
			transient: false,
			panic:     false,
			errorType: "normal",
		},
		{
			name:      "Wrap retriable error",
			fn:        func() error { return Wrap(fmt.Errorf("oops"), "extra").With(MarkRetriable()) },
			msg:       "extra: oops",
			retriable: true,
			transient: true,
			panic:     false,
			errorType: "retriable",
		},
		{
			name:      "Wrapf normal error",
			fn:        func() error { return Wrapf(New("oops"), "extra %d", 1) },
			msg:       "extra 1: oops",
			retriable: false,
			transient: false,
			panic:     false,
			errorType: "normal",
		},
		{
			name:      "Wrap retriable error",
			fn:        func() error { return Wrapf(New("oops"), "extra %d", 1).With(MarkRetriable()) },
			msg:       "extra 1: oops",
			retriable: true,
			transient: true,
			panic:     false,
			errorType: "retriable",
		},
		{
			name:      "returning a normal error",
			fn:        func() error { return fmt.Errorf("oops") },
			msg:       "oops",
			retriable: false,
			transient: false,
			panic:     false,
			errorType: "normal",
		},
		{
			name:      "New transient error",
			fn:        func() error { return New("oops").With(MarkTransient()) },
			msg:       "oops",
			retriable: false,
			transient: true,
			panic:     false,
			errorType: "transient",
		},
		{
			name:      "New panic error",
			fn:        func() error { return New("oops").With(MarkPanic()) },
			msg:       "oops",
			retriable: false,
			transient: false,
			panic:     true,
			errorType: "panic",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := test.fn()

			r.Error(err)
			r.Equal(test.retriable, IsRetriable(err))
			r.Equal(test.transient, IsTransient(err))
			r.Equal(test.panic, IsPanic(err))
			r.Equal(test.msg, err.Error())
			r.Equal(test.errorType, Type(err))
		})
	}
}
