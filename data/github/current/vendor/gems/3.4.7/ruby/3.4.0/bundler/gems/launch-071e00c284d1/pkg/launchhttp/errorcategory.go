package launchhttp

import (
	"context"
	"errors"
	"io"
	"net"
	"net/url"
	"os"
	"strings"

	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

const (
	ErrCategoryUnknown              = "unknown"
	ErrCategoryTimeout              = "timeout"
	ErrCategoryHeaderTimeout        = "resp_header"
	ErrCategoryTemporary            = "temporary"
	ErrCategoryEOF                  = "eof"
	ErrCategoryUnexpectedEOF        = "unexpected_eof"
	ErrCategoryClosed               = "closed"
	ErrCategoryWriteToConn          = "write_conn"
	ErrCategoryDNSConfig            = "dns_config"
	ErrCategoryDNSError             = "dns_error"
	ErrCategoryAddrError            = "addr_error"
	ErrCategoryParseError           = "parse_error" // Used for net.ParseError errors
	ErrCategoryOpError              = "op_error"
	ErrCategorySyscallError         = "syscall_error"
	ErrCategoryContextCancelled     = "context_cancelled"
	ErrCategoryContextDeadline      = "context_deadline"
	ErrCategoryAZP                  = "azp"
	ErrCategoryAZPRerunPlanNotFound = ErrCategoryAZP + "_rerun_plan_not_found"
	ErrCategoryAZPSyntax            = ErrCategoryAZP + "_syntax"
	ErrCategoryAZP429               = ErrCategoryAZP + "_429"
	ErrCategoryWorkflowParse        = "workflow_syntax" // Used for actions-workflow-parser errors

	httpTimeoutRespHeadersErr = "net/http: timeout awaiting response headers"
)

// GetLowCardinalityErrorCategory attempts to determine the category of the error and return a string. This is to avoid high-cardinality
// error categories in our metric systems.
func GetLowCardinalityErrorCategory(err error) string {

	// Let's unwrap the error
	for errors.Unwrap(err) != nil {
		err = errors.Unwrap(err)
	}

	category := ErrCategoryUnknown

	errs := make([]error, 0, 2)
	errs = append(errs, err)

	// Note that net/http's *Client.Do returns a *url.Error per its documentation:
	//
	// Any returned error will be of type *url.Error. The url.Error
	// value's Timeout method will report true if the request timed out.
	//
	// But this isn't always true in practice, so we check both errors
	var urlErr *url.Error
	if ok := errors.As(err, &urlErr); ok {
		errs = append(errs, urlErr.Err)
	}

	for _, e := range errs {
		category = evalErrorChain(e)
		// leave early
		if category != ErrCategoryUnknown {
			return category
		}
		category = evalErrorType(e)
		// leave early
		if category != ErrCategoryUnknown {
			return category
		}
	}
	return category
}

func evalErrorChain(e error) string {
	switch {
	case errors.Is(e, io.EOF):
		return ErrCategoryEOF
	case errors.Is(e, io.ErrUnexpectedEOF):
		return ErrCategoryUnexpectedEOF
	case errors.Is(e, net.ErrClosed):
		return ErrCategoryClosed
	case errors.Is(e, net.ErrWriteToConnected):
		return ErrCategoryWriteToConn
	case errors.Is(e, context.Canceled):
		return ErrCategoryContextCancelled
	case errors.Is(e, context.DeadlineExceeded):
		return ErrCategoryContextDeadline
	default:
		return ErrCategoryUnknown
	}
}

func evalErrorType(e error) string {
	category := ErrCategoryUnknown
	switch terr := e.(type) {
	case *azperrors.AZPError:
		errorCode := ""
		if terr.ExceptionType != "" {
			errorCode = "_" + strings.ToLower(terr.ExceptionType)
		}

		if terr.StatusCode != 0 {
			errorCode += "_" + GetMetricTagForStatusCode(terr.StatusCode)
		}

		if errorCode == "" {
			errorCode = "_" + ErrCategoryUnknown
		}

		category = ErrCategoryAZP + errorCode
	case *azperrors.AZPRawResponseError:
		errorCode := ""
		if terr.StatusCode != 0 {
			errorCode = errorCode + GetMetricTagForStatusCode(terr.StatusCode)
		}

		if errorCode == "" {
			errorCode = ErrCategoryUnknown
		}

		category = ErrCategoryAZP + "_" + errorCode
	case *azperrors.RerunPlanNotFoundError:
		category = ErrCategoryAZPRerunPlanNotFound
	case *azperrors.AZPSyntaxError:
		category = ErrCategoryAZPSyntax
	case *azperrors.TooManyBuildsError:
		category = ErrCategoryAZP429
	case *wfparser.WorkflowParseError:
		category = ErrCategoryWorkflowParse
	case *net.DNSConfigError:
		category = ErrCategoryDNSConfig
	case *net.DNSError:
		category = ErrCategoryDNSError
	case *net.AddrError:
		category = ErrCategoryAddrError
	case *net.ParseError:
		category = ErrCategoryParseError
	case *net.OpError:
		category = ErrCategoryOpError
		if terr.Op != "" {
			category += "_" + terr.Op
		}
		if terr.Net != "" {
			category += "_" + terr.Net
		}
	case *os.SyscallError:
		category = ErrCategorySyscallError
	case interface {
		Timeout() bool
		Temporary() bool
		Error() string
	}:
		compositeCategory := make([]string, 0, 3)
		if terr.Temporary() {
			compositeCategory = append(compositeCategory, ErrCategoryTemporary)
		}
		if terr.Error() == httpTimeoutRespHeadersErr {
			compositeCategory = append(compositeCategory, ErrCategoryHeaderTimeout)
		}
		if terr.Timeout() {
			compositeCategory = append(compositeCategory, ErrCategoryTimeout)
		}
		if len(compositeCategory) > 0 {
			category = ""
			for idx, c := range compositeCategory {
				if idx > 0 {
					category += "_"
				}
				category += c
			}
		}
	case interface{ Code() int }:
		category = GetMetricTagForStatusCode(terr.Code())
	}
	return category
}
