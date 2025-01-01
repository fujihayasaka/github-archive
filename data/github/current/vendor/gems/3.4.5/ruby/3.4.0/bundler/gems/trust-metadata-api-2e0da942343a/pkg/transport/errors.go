package transport

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/twitchtv/twirp"
)

var (
	ErrInvalidPredicateType    = twirp.InvalidArgumentError("predicate_type", "invalid predicate type provided")
	ErrTooManySubjectDigests   = twirp.InvalidArgumentError("subject_digests", fmt.Sprintf("too many digests provided, limit is %d", attestation.SubjectLimit))
	ErrNoAttestationIDs        = twirp.InvalidArgumentError("attestation_ids", "no attestation IDs provided")
	ErrTooManyAttestationIDs   = twirp.InvalidArgumentError("attestation_ids", fmt.Sprintf("too many attestation IDs provided, limit is %d", attestation.SubjectLimit))
	ErrNoMatchingAttestations  = twirp.NotFoundError("no matching attestations found")
	ErrNoSubjectDigestArg      = twirp.InvalidArgumentError("subject_digest,subject_digests", "either argument must be provided")
	ErrNoSubjectDigests        = twirp.InvalidArgumentError("subject_digests", "no subject digests provided")
	ErrOnlyOneSubjectDigestArg = twirp.InvalidArgumentError("subject_digest,subject_digests", "only one argument may be provided")
	ErrUnsupportedClient       = twirp.InternalError("client ID does not match any supported client")
)

// GetTwirpError converts known service errors into their corresponding twirp.Error
func getTwirpError(e error) twirp.Error {
	var ua *service.InternalError
	if errors.As(e, &ua) {
		return twirp.WrapError(twirp.Internal.Error(ua.ClientFacingError()), ua)
	}
	var be *service.BadRequestError
	if errors.As(e, &be) {
		return twirp.WrapError(twirp.InvalidArgument.Error(be.ClientFacingError()), be)
	}
	var ce *service.ConflictError
	if errors.As(e, &ce) {
		return twirp.WrapError(twirp.AlreadyExists.Error(ce.ClientFacingError()), ce)
	}
	var nfe *service.NotFoundError
	if errors.As(e, &nfe) {
		return twirp.WrapError(twirp.NotFound.Error(nfe.ClientFacingError()), nfe)
	}

	return twirp.InternalErrorWith(e)
}

// Twirp interceptor to translate service errors into the appropriate twirp
// error. Anything which is already a twirp error is passed through unchanged.
// Twirp ultimately expect all errors to be Twirp errors, if they are not they
// will be converted to an InternalError. This is our last opportunity to map
// our internal errors to the appropriate Twirp error and ensure that the most
// appropriate status code is returned.
func translateServiceErrorInterceptor() twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			resp, err := next(ctx, req)

			if err != nil {
				// If the error is not a twirp error, convert it to a twirp error
				var twerr twirp.Error
				if !errors.As(err, &twerr) {
					err = getTwirpError(err)
				}
			}

			return resp, err
		}
	}
}

func errorHooks(logger log.Logger, reporter *exceptions.Reporter) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, err twirp.Error) context.Context {
			if errors.Is(err, ErrNoMatchingAttestations) {
				// Don't log or process 404
				return ctx
			}

			errType, errorToReport := innerError(err)

			// Collect all the metadata we want to attach to error reports and
			// log entries
			meta := map[string]string{}
			if errType != "" {
				meta[o11y.ErrTypeLabel] = errType
			}
			meta[o11y.GitHubRequestIDLabel] = requestid.GetGitHubRequestID(ctx)

			if npmReqID, ok := ctx.Value(o11y.NpmCtxKeyName).(string); ok {
				meta[o11y.NpmRequestIDLabel] = npmReqID
			}

			// Report Error if it is a known or internal error type
			if errType != "" && reporter != nil {
				// Apply the "#" prefix to all metadata keys sent to Sentry
				taggedMeta := map[string]string{}
				for k, v := range meta {
					taggedMeta["#"+k] = v
				}

				_ = reporter.Report(ctx, errorToReport, taggedMeta)
			}

			// Format metadata for logging
			fields := []kvp.Field{}
			for k, v := range meta {
				fields = append(fields, kvp.String(k, v))
			}

			logger.Error(errorToReport.Error(), fields...)

			return ctx
		},
	}
}

func innerError(err error) (string, error) {
	// If the error wrapped by the twirp error is a service.InternalError, that is
	// the error we want to report
	var errInternal *service.InternalError
	if errors.As(err, &errInternal) {
		switch {
		case errors.As(errInternal, new(*mysql.ErrGetRecord)):
			return "mysql_read", errInternal
		case errors.As(errInternal, new(*mysql.ErrStoreRecord)):
			return "mysql_write", errInternal
		case errors.As(errInternal, new(*mysql.ErrConvertFromSQLC)):
			fallthrough
		case errors.As(errInternal, new(*mysql.ErrConvertToSQLC)):
			return "sqlc_conversion", errInternal
		case errors.As(errInternal, new(*azureblob.ErrBlobDownloadFailed)):
			return "blob_storage_download", errInternal
		case errors.As(errInternal, new(*azureblob.ErrBlobUploadFailed)):
			return "blob_storage_upload", errInternal
		default:
			return "internal", errInternal
		}
	}

	// Otherwise, just report the twirp error
	return "", err
}
