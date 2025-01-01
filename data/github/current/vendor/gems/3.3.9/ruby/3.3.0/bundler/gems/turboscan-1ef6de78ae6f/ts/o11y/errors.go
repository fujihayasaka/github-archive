package o11y

import "context"

type ExceptionReporter interface {
	Report(ctx context.Context, exception error, payload map[string]string) error
	ReportSensitive(ctx context.Context, exception error, payload, sensitivePayload map[string]string) error
}
