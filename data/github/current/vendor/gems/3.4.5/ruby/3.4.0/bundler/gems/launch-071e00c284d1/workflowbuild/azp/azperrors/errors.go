package azperrors

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/github/go-exceptions"
	"github.com/github/go-kvp"
	errs "github.com/pkg/errors"

	svcerr "github.com/github/launch/services/errors"
)

// An unmarshalled azp exception, plus context like the status code.
type AZPError struct {
	StatusCode int
	// ExceptionType is clearer than the json's "TypeKey"
	ExceptionType string
	Message       string
	context       *kvp.KVP
}

var _ exceptions.RollupInfoer = (*AZPError)(nil)

func (e *AZPError) RollupInfo() string {
	return e.ExceptionType
}

func (e *AZPError) Error() string {
	return fmt.Sprintf("%v: %v (status code: %v)", e.ExceptionType, e.Message, e.StatusCode)
}

// Context gets sent to Sentry and logging on `.Report`
func (e *AZPError) Context() *kvp.KVP {
	return e.context
}

func (e *AZPError) addContext(field kvp.Field) {
	if e.context == nil {
		e.context = kvp.KVPs(field)
		return
	}
	e.context.Add(field)
}

// An AZP error response that couldn't be parsed as an exception.
type AZPRawResponseError struct {
	StatusCode int
	// The response body
	Body []byte
	kvp  *kvp.KVP
}

var _ exceptions.RollupInfoer = (*AZPRawResponseError)(nil)

func (e *AZPRawResponseError) Error() string {
	if len(e.Body) == 0 {
		return fmt.Sprintf("AZP returned status code %v", e.StatusCode)
	}
	return fmt.Sprintf("%v (status code: %v)", string(e.Body), e.StatusCode)
}

func (e *AZPRawResponseError) RollupInfo() string {
	return fmt.Sprintf("azp returned status code %v", e.StatusCode)
}

// Context gets sent to Sentry and logging on `.Report`
func (e *AZPRawResponseError) Context() *kvp.KVP {
	return e.kvp
}

// Returns an AZPError or AZPRawResponseError.
func NewErrorFromAZPResponse(body []byte, responseCode int) error {
	errResponse, err := parseErrorBody(body)
	if err != nil {
		bodyOrig := string(body)
		bodyClean := removeUniqueIDs(bodyOrig)
		out := AZPRawResponseError{
			StatusCode: responseCode,
			Body:       []byte(bodyClean),
		}
		if bodyOrig != bodyClean {
			out.kvp = kvp.KVPs(kvp.String("exception.message", bodyOrig))
		}
		return &out
	}

	out := AZPError{
		StatusCode:    responseCode,
		ExceptionType: errResponse.getType(),
		Message:       removeUniqueIDs(errResponse.Message),
	}

	if out.Message != errResponse.Message {
		out.addContext(kvp.String("exception.message", errResponse.Message))
	}

	if errResponse.Ref != "" {
		out.addContext(kvp.String("ref", errResponse.Ref))
	}

	return &out
}

// based on GetHTTPError
func GetAZPError(err error) *AZPError {
	if azpErr, ok := errs.Cause(err).(*AZPError); ok {
		return azpErr
	}

	return nil
}

// Returns a service error and whether the error should be reported for a given error
//
//revive:disable-next-line:error-return
func ToServiceError(err error) (error, bool) {
	// No error
	if err == nil {
		return nil, false
	}
	aerr := GetAZPError(err)
	// No azp error
	if aerr == nil {
		return svcerr.NewInternalError(err.Error()), true
	}

	// Special cases
	if aerr.ExceptionType == TaskAgentJobStillRunningException {
		// Would otherwise be handled as a 400 resulting in InvalidArgumentError
		return svcerr.NewFailedPrecondition(aerr.Message), false
	}
	if aerr.ExceptionType == CannotMoveRunnerIntoOrOutOfVirtualGroupException {
		// Would otherwise be handled as a 500 resulting in InternalError
		return svcerr.NewInvalidArgumentError(aerr.Message), false
	}

	// Propagation
	switch aerr.StatusCode {
	case 400:
		return svcerr.NewInvalidArgumentError(aerr.Message), false
	case 403:
		return svcerr.NewPermissionDeniedError(aerr.Message), false
	case 404:
		return svcerr.NewNotFoundError(aerr.Message), false
	case 409:
		return svcerr.NewAlreadyExistsError(aerr.Message), false
	case 422:
		return svcerr.NewInvalidArgumentError(aerr.Message), false
	default:
		return svcerr.NewInternalError(aerr.Message), true
	}
}

type AzpErrorResponse struct {
	TypeKey string `json:"typeKey"`
	Message string `json:"message"`
	Ref     string `json:"ref"`
}

func (a *AzpErrorResponse) getType() string {
	if a.TypeKey != "" {
		return a.TypeKey
	}
	if a.Ref != "" && strings.Contains(a.Ref, "Ref A") {
		return ActionsScaleUnitUnavailable
	}
	return Exception
}

func parseErrorBody(body []byte) (*AzpErrorResponse, error) {
	errResponse := AzpErrorResponse{}
	if err := json.Unmarshal(body, &errResponse); err != nil {
		return nil, err
	}

	if errResponse.TypeKey == "" && errResponse.Message == "" {
		return nil, errs.New("Body doesn't include 'typeKey' or 'message' properties.")
	}

	return &errResponse, nil
}

// Currently we don't have the same level of validation as AZP, so
// we can have syntax errors that aren't caught by provider.ParseFlow. This
// error is passed around to handle it.
type AZPSyntaxError struct {
	SyntaxErrorMessage string
}

func (a *AZPSyntaxError) Error() string {
	return a.SyntaxErrorMessage
}

var errorPositionRegex = regexp.MustCompile(`\(Line: (\d+), Col: (\d+)\):`)

// Position returns the line and column the error occured on. -1 for both values if the position cannot
// be parsed.
func (a *AZPSyntaxError) Position() (int, int) {
	matches := errorPositionRegex.FindStringSubmatch(a.SyntaxErrorMessage)
	if matches == nil || len(matches) < 3 {
		return -1, -1
	}

	line, err := strconv.ParseInt(matches[1], 10, 32)
	if err != nil {
		return -1, -1
	}

	col, err := strconv.ParseInt(matches[2], 10, 32)
	if err != nil {
		return -1, -1
	}

	return int(line), int(col)
}

func NewInvalidSyntaxError(msg string) error {
	return &AZPSyntaxError{SyntaxErrorMessage: msg}
}

// RerunPlanNotFoundError represents an error on a partial rerun where the original run
// no longer exists. This is unlikely but will occur if their log retention is less than
// the 30 days we show the Rerun button in the UI. It is considered IsUserError() => true
// in order to show the returned error to the user, instead of the default generic
// "something went wrong, contact us" error.
type RerunPlanNotFoundError struct{ msg string }

func (e *RerunPlanNotFoundError) Error() string     { return e.msg }
func (e *RerunPlanNotFoundError) IsUserError() bool { return true }
func NewRerunPlanNotFoundError(msg string) error    { return &RerunPlanNotFoundError{msg} }

// TooManyBuildsError represents an error when Actions Service returns a http 429 too many requests
// error code when queuing a build.
type TooManyBuildsError struct {
}

func (e *TooManyBuildsError) Error() string {
	return "Too many builds queued"
}

var uniqueIDCleaner = regexp.MustCompile(`(Activity Id:|with the name|with identifier) [\S]*`)
var uuidCleaner = regexp.MustCompile(`\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b`)

func removeUniqueIDs(str string) string {
	str = uniqueIDCleaner.ReplaceAllString(str, "$1 ***")
	str = uuidCleaner.ReplaceAllString(str, "<uuid>")
	return str
}
