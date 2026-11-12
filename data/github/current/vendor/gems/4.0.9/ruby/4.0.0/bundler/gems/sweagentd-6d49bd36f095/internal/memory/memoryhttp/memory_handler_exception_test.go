package memoryhttp

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
)

// mockExceptionReporter is a simple mock that records calls to Report.
type mockExceptionReporter struct {
	mu      sync.Mutex
	calls   []reportCall
	reportN int
}

type reportCall struct {
	err     error
	payload map[string]string
}

func (m *mockExceptionReporter) Report(_ context.Context, exception error, payload map[string]string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls = append(m.calls, reportCall{err: exception, payload: payload})
	m.reportN++
	return nil
}

func (m *mockExceptionReporter) ReportSensitive(ctx context.Context, exception error, payload, _ map[string]string) error {
	return m.Report(ctx, exception, payload)
}

func (m *mockExceptionReporter) reportCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.reportN
}

func newObsvWithMockReporter(reporter *mockExceptionReporter) observability.Exporters {
	obsv := observability.NewNoopExporters()
	obsv.Reporter = reporter
	return obsv
}

func TestHandleDomainError_ReportsExceptionFor500(t *testing.T) {
	reporter := &mockExceptionReporter{}
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return errors.New("unexpected cosmos error")
		},
	}

	obsv := newObsvWithMockReporter(reporter)
	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv)

	memoryDTO := createTestMemoryDTO()
	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Equal(t, 1, reporter.reportCount(), "expected exception to be reported for 500 error")
}

func TestHandleDomainError_ReportsExceptionFor502(t *testing.T) {
	reporter := &mockExceptionReporter{}
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrSecretScanningServiceUnavailable
		},
	}

	obsv := newObsvWithMockReporter(reporter)
	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv)

	memoryDTO := createTestMemoryDTO()
	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadGateway, rr.Code)
	assert.Equal(t, 1, reporter.reportCount(), "expected exception to be reported for 502 error")
}

func TestHandleDomainError_DoesNotReportFor4xx(t *testing.T) {
	reporter := &mockExceptionReporter{}
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrEmptyRepoNWO
		},
	}

	obsv := newObsvWithMockReporter(reporter)
	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv)

	memoryDTO := createTestMemoryDTO()
	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Equal(t, 0, reporter.reportCount(), "expected no exception report for 4xx error")
}

func TestHandleDomainError_DoesNotReportFor404(t *testing.T) {
	reporter := &mockExceptionReporter{}
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			return core.ErrMemoryNotFound
		},
	}

	obsv := newObsvWithMockReporter(reporter)
	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/some-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Equal(t, 0, reporter.reportCount(), "expected no exception report for 404 error")
}

func TestReportException_SkipsContextCanceled(t *testing.T) {
	reporter := &mockExceptionReporter{}
	obsv := newObsvWithMockReporter(reporter)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Obsv: obsv,
	})

	handler.reportException(context.Background(), context.Canceled)

	assert.Equal(t, 0, reporter.reportCount(), "expected no report for context.Canceled")
}

func TestReportException_SkipsDeadlineExceeded(t *testing.T) {
	reporter := &mockExceptionReporter{}
	obsv := newObsvWithMockReporter(reporter)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Obsv: obsv,
	})

	handler.reportException(context.Background(), context.DeadlineExceeded)

	assert.Equal(t, 0, reporter.reportCount(), "expected no report for context.DeadlineExceeded")
}

func TestReportException_SkipsWrappedContextCanceled(t *testing.T) {
	reporter := &mockExceptionReporter{}
	obsv := newObsvWithMockReporter(reporter)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Obsv: obsv,
	})

	wrappedErr := errors.Join(errors.New("operation failed"), context.Canceled)
	handler.reportException(context.Background(), wrappedErr)

	assert.Equal(t, 0, reporter.reportCount(), "expected no report for wrapped context.Canceled")
}

func TestReportException_ReportsRegularErrors(t *testing.T) {
	reporter := &mockExceptionReporter{}
	obsv := newObsvWithMockReporter(reporter)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Obsv: obsv,
	})

	handler.reportException(context.Background(), errors.New("cosmos connection failed"))

	assert.Equal(t, 1, reporter.reportCount(), "expected report for regular error")
}

func TestCheckMemoryEnabled_ReportsExceptionOnError(t *testing.T) {
	reporter := &mockExceptionReporter{}
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return false, errors.New("database error")
		},
	}

	obsv := newObsvWithMockReporter(reporter)
	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Equal(t, 1, reporter.reportCount(), "expected exception to be reported for enablement check error")
}
