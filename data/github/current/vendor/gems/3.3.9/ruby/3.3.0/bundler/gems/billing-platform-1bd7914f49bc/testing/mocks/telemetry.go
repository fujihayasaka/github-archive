package mocks

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap/zapcore"
)

type Tracer struct{}

func (m Tracer) Start(ctx context.Context, _ string, _ ...trace.SpanStartOption) (context.Context, trace.Span) {
	return ctx, &Span{}
}

type Span struct{}

func (m *Span) End(_ ...trace.SpanEndOption) {}

func (m *Span) AddEvent(_ string, _ ...trace.EventOption) {}
func (m *Span) IsRecording() bool {
	return true
}
func (m *Span) RecordError(_ error, _ ...trace.EventOption) {}
func (m *Span) SetStatus(_ codes.Code, _ string)            {}
func (m *Span) SetName(_ string)                            {}
func (m *Span) SetAttributes(_ ...attribute.KeyValue)       {}
func (m *Span) SpanContext() trace.SpanContext {
	return trace.SpanContext{}
}
func (m *Span) TracerProvider() trace.TracerProvider {
	return nil
}

type Logger struct{}

func (m *Logger) Info(_ string, _ ...zapcore.Field)             {}
func (m *Logger) Warn(_ string, _ ...zapcore.Field)             {}
func (m *Logger) Error(_ string, _ ...zapcore.Field)            {}
func (m *Logger) Debug(_ string, _ ...zapcore.Field)            {}
func (m *Logger) Fatal(_ string, _ ...zapcore.Field)            {}
func (m *Logger) Log(_ log.Level, _ string, _ ...zapcore.Field) {}
func (m *Logger) Named(_ string) log.Logger {
	return m
}
func (m *Logger) Sync() error {
	return nil
}
func (m *Logger) WithContext(_ context.Context) log.Logger {
	return m
}
func (m *Logger) WithError(_ error) log.Logger {
	return m
}
func (m *Logger) WithFields(_ ...zapcore.Field) log.Logger {
	return m
}
func (m *Logger) WithLevel(_ log.Level) log.Logger {
	return m
}

type Statter struct{}

func (m Statter) Start() {}
func (m Statter) Run()   {}
func (m Statter) Stop()  {}

func (m Statter) Report(t stats.Type, key string, value float64, tags stats.Tags, rate float32) {}
func (m Statter) Event(title, text string, tags stats.Tags)                                     {}

func (m Statter) Gauge(key string, tags stats.Tags, value int64)                  {}
func (m Statter) Counter(key string, tags stats.Tags, value int64)                {}
func (m Statter) Histogram(key string, tags stats.Tags, value int64)              {}
func (m Statter) Timing(key string, tags stats.Tags, value time.Duration)         {}
func (m Statter) Distribution(key string, tags stats.Tags, value float64)         {}
func (m Statter) DistributionMs(key string, tags stats.Tags, value time.Duration) {}
func (m Statter) Set(key string, tags stats.Tags, value string)                   {}

func (m Statter) WithTags(tags stats.Tags) stats.Client {
	return m
}
