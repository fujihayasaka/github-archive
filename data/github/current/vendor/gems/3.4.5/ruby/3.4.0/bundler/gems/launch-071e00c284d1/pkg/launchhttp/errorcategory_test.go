package launchhttp

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"

	"github.com/github/launch/pkg/wfparser"
	errtypes "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

var errCategoryTests = []struct {
	err  error
	want string
}{
	{
		err: &url.Error{
			Err: &fakeError{timeout: true},
		},
		want: ErrCategoryTimeout,
	},
	{
		err: &url.Error{
			Err: &fakeError{temporary: true},
		},
		want: ErrCategoryTemporary,
	},
	{
		err: &url.Error{
			Err: io.EOF,
		},
		want: ErrCategoryEOF,
	},
	{
		err: &url.Error{
			Err: io.ErrUnexpectedEOF,
		},
		want: ErrCategoryUnexpectedEOF,
	},
	{
		err: &url.Error{
			Err: net.ErrClosed,
		},
		want: ErrCategoryClosed,
	},
	{
		err: &url.Error{
			Err: net.ErrWriteToConnected,
		},
		want: ErrCategoryWriteToConn,
	},
	{
		err: &url.Error{
			Err: &net.DNSConfigError{},
		},
		want: ErrCategoryDNSConfig,
	},
	{
		err: &url.Error{
			Err: &net.DNSError{},
		},
		want: ErrCategoryDNSError,
	},
	{
		err: &url.Error{
			Err: &net.AddrError{},
		},
		want: ErrCategoryAddrError,
	},
	{
		err: &url.Error{
			Err: &net.ParseError{},
		},
		want: ErrCategoryParseError,
	},
	{
		err: &url.Error{
			Err: &net.OpError{},
		},
		want: ErrCategoryOpError,
	},
	{
		err: &url.Error{
			Err: &os.SyscallError{},
		},
		want: ErrCategorySyscallError,
	},
	{
		err: &url.Error{
			Err: unknownError,
		},
		want: ErrCategoryUnknown,
	},
	{
		err:  io.EOF,
		want: ErrCategoryEOF,
	},
	{
		err:  context.Canceled,
		want: ErrCategoryContextCancelled,
	},
	{
		err:  context.DeadlineExceeded,
		want: ErrCategoryContextDeadline,
	},
	{
		err:  httpErrTimeout,
		want: "temporary_resp_header_timeout",
	},
	{
		err:  &net.OpError{Op: "read", Net: "tcp"},
		want: ErrCategoryOpError + "_read_tcp",
	},
	{
		err:  &azperrors.AZPError{},
		want: ErrCategoryAZP + "_" + ErrCategoryUnknown,
	},
	{
		err: &azperrors.AZPError{
			ExceptionType: azperrors.ActionsScaleUnitUnavailable,
		},
		want: ErrCategoryAZP + "_" + strings.ToLower(azperrors.ActionsScaleUnitUnavailable),
	},
	{
		err: &azperrors.AZPError{
			ExceptionType: azperrors.ActionsScaleUnitUnavailable,
			StatusCode:    503,
		},
		want: ErrCategoryAZP + "_" + strings.ToLower(azperrors.ActionsScaleUnitUnavailable+"_service_unavailable"),
	},
	{
		err: &azperrors.AZPRawResponseError{
			StatusCode: 503,
		},
		want: ErrCategoryAZP + "_service_unavailable",
	},
	{
		err:  &azperrors.AZPRawResponseError{},
		want: ErrCategoryAZP + "_" + ErrCategoryUnknown,
	},
	{
		err:  &azperrors.RerunPlanNotFoundError{},
		want: ErrCategoryAZPRerunPlanNotFound,
	},
	{
		err:  &azperrors.AZPSyntaxError{},
		want: ErrCategoryAZPSyntax,
	},
	{
		err:  &azperrors.TooManyBuildsError{},
		want: ErrCategoryAZP429,
	},
	{
		err:  &wfparser.WorkflowParseError{},
		want: ErrCategoryWorkflowParse,
	},
	{
		err:  errtypes.NewHTTPError(&http.Response{StatusCode: 404}),
		want: "not_found",
	},
}

func Test_GetLowCardinalityErrorCategory(t *testing.T) {
	for _, tt := range errCategoryTests {
		t.Run(fmt.Sprintf("%T", tt.err), func(t *testing.T) {
			if got := GetLowCardinalityErrorCategory(tt.err); got != tt.want {
				t.Errorf("inspectHTTPErr() = %v, want %v", got, tt.want)
			}
		})
	}
}

func Benchmark_GetLowCardinalityErrorCategory(b *testing.B) {
	for _, tt := range errCategoryTests {
		b.Run(fmt.Sprintf("%T", tt.err), func(_ *testing.B) {
			for n := 0; n < b.N; n++ {
				GetLowCardinalityErrorCategory(tt.err)
			}
		})
	}
}

type fakeError struct {
	temporary bool
	timeout   bool
}

func (t *fakeError) Temporary() bool { return t.temporary }
func (t *fakeError) Timeout() bool   { return t.timeout }
func (t *fakeError) Error() string   { return "" }

var unknownError = errors.New(ErrCategoryUnknown)

// Vendoring this in for testing purposes from:
// https://cs.github.com/golang/go/blob/38174b3a3514629b84dcd76878b2f536b189dd7b/src/net/http/transport.go#L2504-L2513
type fakeHttpError struct {
	err     string
	timeout bool
}

func (e *fakeHttpError) Error() string   { return e.err }
func (e *fakeHttpError) Timeout() bool   { return e.timeout }
func (e *fakeHttpError) Temporary() bool { return true }

var httpErrTimeout error = &fakeHttpError{err: httpTimeoutRespHeadersErr, timeout: true}
