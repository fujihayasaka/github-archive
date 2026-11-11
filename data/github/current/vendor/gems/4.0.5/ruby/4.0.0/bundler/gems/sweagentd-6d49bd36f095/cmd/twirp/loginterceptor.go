package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/requestctx"

	"github.com/github/go-twirp/v2/server"
	"github.com/github/go-twirp/v2/server/hooks"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// LogInterceptor returns a Twirp interceptor that emits a single log event
// for each request with full context, including TraceId from the active span.
func LogInterceptor(l log.Logger) twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req any) (resp any, err error) {
			const messageBody = "twirp request"
			fields := []kvp.Field{
				kvp.String("component", "twirp"),
			}
			if mthd, ok := twirp.MethodName(ctx); ok {
				fields = append(fields, kvp.String(server.MethodNameLabel, mthd))
			}
			if svc, ok := twirp.ServiceName(ctx); ok {
				fields = append(fields, kvp.String(server.ServiceNameLabel, svc))
			}
			if pkg, ok := twirp.PackageName(ctx); ok {
				fields = append(fields, kvp.String(server.PackageNameLabel, pkg))
			}
			fields = append(fields, extractProtoFields(req)...)

			start := time.Now()

			defer func() {
				r := recover()
				if r != nil {
					// Panic should be logged as an internal error
					err = goerrors.Errorf("panic: %v", r)
				}

				// Include requestctx telemetry fields after request handling,
				// so fields populated during the handler (e.g., job, session, repo)
				// are captured in the log.
				_, _, reqCtxFields := requestctx.ToTelemetry(ctx, nil)
				fields = append(fields, reqCtxFields...)

				fields = append(fields,
					kvp.Duration(hooks.RequestDurationLabel, time.Since(start)),
				)
				// Enrich the logger with TraceId/SpanId from the active OTel span
				enrichedLogger := l.WithSpanContext(ctx)
				statusCode := inferStatusCode(err)
				fields = append(fields, kvp.Int(server.StatusCodeLabel, statusCode))
				if err != nil {
					fields = append(fields,
						kvp.String("exception.message", err.Error()),
						kvp.String("exception.type", fmt.Sprintf("%T", err)),
					)
				}
				switch {
				case statusCode >= 500:
					enrichedLogger.Error(messageBody, fields...)
				case statusCode >= 400:
					enrichedLogger.Warn(messageBody, fields...)
				default:
					enrichedLogger.Info(messageBody, fields...)
				}
				// re-raise the panic if it occurred
				if r != nil {
					panic(r)
				}
			}()

			resp, err = next(ctx, req)
			return resp, err
		}
	}
}

// inferStatusCode returns the HTTP status code that should be returned for a given twirp error. If the error is nil,
// it returns 200. For a twirp.Error, it returns the mapped status code. Otherwise 500 (twirp.Internal) is returned.
func inferStatusCode(err error) int {
	if err == nil {
		return twirp.ServerHTTPStatusFromErrorCode(twirp.NoError)
	}

	code := twirp.Internal
	var twerr twirp.Error
	if errors.As(err, &twerr) {
		code = twerr.Code()
	}

	return twirp.ServerHTTPStatusFromErrorCode(code)
}

// extractProtoFields extracts fields from a protobuf message using reflection.
func extractProtoFields(msg any) []kvp.Field {
	fields := []kvp.Field{}

	protoMsg, ok := msg.(proto.Message)
	if !ok {
		return fields
	}
	m := protoMsg.ProtoReflect()

	m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		fieldName := "request." + string(fd.Name())

		// We should only log id fields to avoid leaking sensitive information
		if !strings.HasSuffix(fieldName, "id") {
			return true
		}

		if fd.Cardinality() == protoreflect.Repeated {
			list := v.List()
			if list.Len() == 0 {
				return true // skip empty repeated fields
			}
			// For repeated fields, log up to the first 100 items joined under the base field name
			items := []string{}
			for i := 0; i < list.Len() && i < 100; i++ {
				items = append(items, list.Get(i).String())
			}
			fields = append(fields, kvp.String(fieldName, strings.Join(items, ",")))
			return true
		}

		switch fd.Kind() {
		case protoreflect.StringKind:
			fields = append(fields, kvp.String(fieldName, v.String()))

		case protoreflect.Uint64Kind, protoreflect.Uint32Kind:
			fields = append(fields, kvp.Uint64(fieldName, v.Uint()))

		case protoreflect.Int64Kind, protoreflect.Int32Kind:
			fields = append(fields, kvp.Int64(fieldName, v.Int()))

		case protoreflect.BoolKind:
			fields = append(fields, kvp.Bool(fieldName, v.Bool()))

		case protoreflect.EnumKind:
			enumVal := fd.Enum().Values().ByNumber(v.Enum())
			if enumVal != nil {
				fields = append(fields, kvp.String(fieldName, string(enumVal.Name())))
			}
		case protoreflect.BytesKind:
			fields = append(fields, kvp.String(fieldName, fmt.Sprintf("%d bytes", len(v.Bytes()))))
		default:
			// Skip unknown/complex kinds (messages, maps, etc.) to avoid leaking nested structures
		}
		return true
	})

	return fields
}
