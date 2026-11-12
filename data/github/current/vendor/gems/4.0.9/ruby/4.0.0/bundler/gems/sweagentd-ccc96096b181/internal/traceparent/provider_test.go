package traceparent

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

func TestSign(t *testing.T) {
	secret := []byte("test-secret-key")
	traceparent := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

	signed := sign(traceparent, secret)

	// Should contain the original traceparent
	if !strings.HasPrefix(signed, traceparent+".") {
		t.Errorf("signed traceparent should start with original traceparent, got %q", signed)
	}

	// Should have a signature after the dot
	parts := strings.SplitN(signed, ".", 2)
	if len(parts) != 2 || parts[1] == "" {
		t.Error("signed traceparent should have format 'traceparent.signature'")
	}
}

func TestVerify(t *testing.T) {
	secret := []byte("test-secret-key")
	traceparent := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

	signed := sign(traceparent, secret)

	// Should verify successfully with correct secret
	result, ok := verify(signed, secret)
	if !ok {
		t.Error("verify should succeed with correct secret")
	}
	if result != traceparent {
		t.Errorf("verify returned %q, want %q", result, traceparent)
	}

	// Should fail with wrong secret
	_, ok = verify(signed, []byte("wrong-secret"))
	if ok {
		t.Error("verify should fail with wrong secret")
	}

	// Should fail with tampered traceparent
	tampered := "00-0000000000000000000000000000000-00f067aa0ba902b7-01" + signed[len(traceparent):]
	_, ok = verify(tampered, secret)
	if ok {
		t.Error("verify should fail with tampered traceparent")
	}

	// Should fail with no signature
	_, ok = verify(traceparent, secret)
	if ok {
		t.Error("verify should fail with unsigned traceparent")
	}
}

func TestMiddleware(t *testing.T) {
	secret := []byte("test-secret-key-for-middleware")

	// Sign the traceparent using the Propagator
	traceID, _ := trace.TraceIDFromHex("4bf92f3577b34da6a3ce929d0e0e4736")
	spanID, _ := trace.SpanIDFromHex("00f067aa0ba902b7")
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
	})
	ctx := trace.ContextWithSpanContext(context.Background(), spanContext)

	propagator, err := NewPropagator(secret)
	if err != nil {
		t.Fatalf("failed to create propagator: %v", err)
	}
	signed, err := propagator.GetCopilotTraceparent(ctx)
	if err != nil {
		t.Fatalf("failed to get trace context: %v", err)
	}

	// Create a test handler that verifies the trace context was set
	handlerCalled := false
	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true

		// Extract the span context from the request context
		spanCtx := trace.SpanContextFromContext(r.Context())

		// Verify the trace context was set correctly
		if !spanCtx.IsValid() {
			t.Error("span context should be valid")
		}

		if spanCtx.TraceID().String() != "4bf92f3577b34da6a3ce929d0e0e4736" {
			t.Errorf("trace ID = %s, want 4bf92f3577b34da6a3ce929d0e0e4736", spanCtx.TraceID().String())
		}

		w.WriteHeader(http.StatusOK)
	})

	// Wrap handler with middleware
	middleware, err := Middleware(secret)
	if err != nil {
		t.Fatalf("failed to create middleware: %v", err)
	}
	handler := middleware(testHandler)

	// Create a request with the signed traceparent header
	req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
	req.Header.Set(XCopilotTraceparentHeader, signed)

	// Record the response
	rr := httptest.NewRecorder()

	// Serve the request
	handler.ServeHTTP(rr, req)

	if !handlerCalled {
		t.Error("handler was not called")
	}

	if rr.Code != http.StatusOK {
		t.Errorf("status code = %d, want %d", rr.Code, http.StatusOK)
	}
}

func TestMiddleware_NoHeader(t *testing.T) {
	secret := []byte("test-secret-key")

	// Create a test handler
	handlerCalled := false
	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true
		w.WriteHeader(http.StatusOK)
	})

	// Wrap handler with middleware
	middleware, err := Middleware(secret)
	if err != nil {
		t.Fatalf("failed to create middleware: %v", err)
	}
	handler := middleware(testHandler)

	// Create a request without the header
	req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
	rr := httptest.NewRecorder()

	// Serve the request
	handler.ServeHTTP(rr, req)

	if !handlerCalled {
		t.Error("handler was not called")
	}

	if rr.Code != http.StatusOK {
		t.Errorf("status code = %d, want %d", rr.Code, http.StatusOK)
	}
}

func TestMiddleware_InvalidSignature(t *testing.T) {
	secret := []byte("test-secret-key")

	// Create a test handler that checks trace context was NOT set
	handlerCalled := false
	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true

		// Trace context should NOT be valid since signature is invalid
		spanCtx := trace.SpanContextFromContext(r.Context())
		if spanCtx.IsValid() {
			t.Error("span context should not be valid with invalid signature")
		}

		w.WriteHeader(http.StatusOK)
	})

	// Wrap handler with middleware
	middleware, err := Middleware(secret)
	if err != nil {
		t.Fatalf("failed to create middleware: %v", err)
	}
	handler := middleware(testHandler)

	// Create a request with an invalid signed header
	req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
	req.Header.Set(XCopilotTraceparentHeader, "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01.invalid-signature")
	rr := httptest.NewRecorder()

	// Serve the request - should not fail, just ignore invalid signature
	handler.ServeHTTP(rr, req)

	if !handlerCalled {
		t.Error("handler was not called")
	}

	if rr.Code != http.StatusOK {
		t.Errorf("status code = %d, want %d", rr.Code, http.StatusOK)
	}
}

func TestMiddleware_Integration(t *testing.T) {
	secret := []byte("integration-test-secret")

	// Set up OpenTelemetry propagator
	otel.SetTextMapPropagator(propagation.TraceContext{})

	// Create initial context with trace
	traceID, _ := trace.TraceIDFromHex("4bf92f3577b34da6a3ce929d0e0e4736")
	spanID, _ := trace.SpanIDFromHex("00f067aa0ba902b7")
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
	})
	sourceCtx := trace.ContextWithSpanContext(context.Background(), spanContext)

	// Sign using the Propagator
	propagator, err := NewPropagator(secret)
	if err != nil {
		t.Fatalf("failed to create propagator: %v", err)
	}
	signed, err := propagator.GetCopilotTraceparent(sourceCtx)
	if err != nil {
		t.Fatalf("GetCopilotTraceparent failed: %v", err)
	}

	// Create handler that checks trace context
	verified := false
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		spanCtx := trace.SpanContextFromContext(r.Context())
		if spanCtx.IsValid() && spanCtx.TraceID().String() == "4bf92f3577b34da6a3ce929d0e0e4736" {
			verified = true
		}
		w.WriteHeader(http.StatusOK)
	})

	// Wrap with middleware
	middleware, err := Middleware(secret)
	if err != nil {
		t.Fatalf("failed to create middleware: %v", err)
	}
	wrappedHandler := middleware(handler)

	// Make request
	req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
	req.Header.Set(XCopilotTraceparentHeader, signed)
	rr := httptest.NewRecorder()

	wrappedHandler.ServeHTTP(rr, req)

	if !verified {
		t.Error("trace context was not properly propagated through middleware")
	}
}

func TestMiddleware_EmptySecret(t *testing.T) {
	_, err := Middleware([]byte(""))
	if err == nil {
		t.Error("Middleware with empty secret should return error")
	}

	_, err = Middleware(nil)
	if err == nil {
		t.Error("Middleware with nil secret should return error")
	}
}

func TestPropagator_Signing(t *testing.T) {
	secret := []byte("test-signing-secret")
	propagator, err := NewPropagator(secret)
	if err != nil {
		t.Fatalf("failed to create propagator: %v", err)
	}

	traceID, _ := trace.TraceIDFromHex("4bf92f3577b34da6a3ce929d0e0e4736")
	spanID, _ := trace.SpanIDFromHex("00f067aa0ba902b7")
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
	})
	ctx := trace.ContextWithSpanContext(context.Background(), spanContext)

	traceContext, err := propagator.GetCopilotTraceparent(ctx)
	if err != nil {
		t.Fatalf("GetCopilotTraceparent failed: %v", err)
	}

	// Should return signed format (traceparent.signature)
	if traceContext == "" {
		t.Error("expected non-empty trace context")
	}

	// Should contain the original traceparent
	expectedPrefix := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01."
	if !strings.HasPrefix(traceContext, expectedPrefix) {
		t.Errorf("expected trace context to start with %q, got %q", expectedPrefix, traceContext)
	}

	// Should be verifiable
	_, ok := verify(traceContext, secret)
	if !ok {
		t.Error("signed traceparent should be verifiable")
	}
}

func TestPropagator_Noop(t *testing.T) {
	// Empty secret means no signing
	propagator, err := NewPropagator(nil)
	if err != nil {
		t.Fatalf("failed to create propagator: %v", err)
	}

	traceID, _ := trace.TraceIDFromHex("4bf92f3577b34da6a3ce929d0e0e4736")
	spanID, _ := trace.SpanIDFromHex("00f067aa0ba902b7")
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
	})
	ctx := trace.ContextWithSpanContext(context.Background(), spanContext)

	traceContext, err := propagator.GetCopilotTraceparent(ctx)
	if err != nil {
		t.Fatalf("GetCopilotTraceparent failed: %v", err)
	}

	// Should return raw W3C traceparent (no signature)
	expected := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
	if traceContext != expected {
		t.Errorf("got %q, want %q", traceContext, expected)
	}
}

func TestPropagator_NoSpanContext(t *testing.T) {
	propagator, err := NewPropagator([]byte("test-secret"))
	if err != nil {
		t.Fatalf("failed to create propagator: %v", err)
	}

	traceContext, err := propagator.GetCopilotTraceparent(context.Background())
	if err != nil {
		t.Fatalf("GetCopilotTraceparent failed: %v", err)
	}

	if traceContext != "" {
		t.Errorf("expected empty trace context for context without span, got %q", traceContext)
	}
}
