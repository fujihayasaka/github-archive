package logger

import (
	"context"
	"testing"

	otellog "github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/log/logtest"
	"github.com/github/go-kvp"
	"github.com/github/go-log"
	"github.com/stretchr/testify/require"
)

func TestLoggerAdapter(t *testing.T) {
	tests := []struct {
		name         string
		ctx          context.Context
		apply        func(log.FieldLogger)
		wantContains []string
	}{
		{
			name: "info",
			ctx:  context.Background(),
			apply: func(ll log.FieldLogger) {
				ll.Info("hello world", kvp.String("key", "val"))
			},
			wantContains: []string{"SeverityText=INFO", `Body="hello world"`, "key=val"},
		},
		{
			name: "debug",
			ctx:  context.Background(),
			apply: func(ll log.FieldLogger) {
				ll.Debug("hello world", kvp.String("key", "val"))
			},
			wantContains: []string{"SeverityText=DEBUG", `Body="hello world"`, "key=val"},
		},
		{
			name: "error",
			ctx:  context.Background(),
			apply: func(ll log.FieldLogger) {
				ll.Error("hello world", kvp.String("key", "val"))
			},
			wantContains: []string{"SeverityText=ERROR", `Body="hello world"`, "key=val"},
		},
		{
			name: "with",
			ctx:  context.Background(),
			apply: func(ll log.FieldLogger) {
				ll.With(kvp.String("key", "val")).Info("hello world")
			},
			wantContains: []string{"SeverityText=INFO", `Body="hello world"`, "key=val"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			log, buf := logtest.NewTestLogger(t, otellog.WithLogLevel(otellog.DebugLevel))
			ll := AdaptToFieldLogger(tt.ctx, &logger{l: log})
			tt.apply(ll)

			got := buf.String()

			for _, wantString := range tt.wantContains {
				require.Contains(t, got, wantString)
			}
		})
	}
}
