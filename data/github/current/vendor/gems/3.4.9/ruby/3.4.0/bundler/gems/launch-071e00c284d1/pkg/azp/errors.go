package azp

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"

	"github.com/pkg/errors"

	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// ResponseValidator returns false, nil for status codes between 200 and 299,
// and a retryable boolean and _always_ an error for all status codes outside
// of that range.
func ResponseValidator() httpclient.ResponseValidator {
	return func(r *http.Response) (bool, error) {
		switch r.StatusCode / 100 {
		case 1, 2, 3:
			return false, nil
		default:
			return handleInvalidResponse(r)
		}
	}
}

func handleInvalidResponse(r *http.Response) (retryable bool, err error) {
	if r.Body != nil {
		var body []byte
		body, err = io.ReadAll(r.Body)
		defer r.Body.Close()

		if err == nil {
			err = azperrors.NewErrorFromAZPResponse(body, r.StatusCode)
		} else {
			err = errors.Wrap(err, fmt.Sprintf("reading body of error %d status code response", r.StatusCode))
		}
	}

	// retry by default for non-4xx responses
	retryable = r.StatusCode >= 500
	switch r.StatusCode {
	case http.StatusBadRequest:
		azpErr := azperrors.GetAZPError(err)
		if azpErr != nil {
			switch azpErr.ExceptionType {
			case azperrors.PipelineValidationException:
				err = azperrors.NewInvalidSyntaxError(azpErr.Message)
			case azperrors.RerunPlanNotFoundException:
				err = azperrors.NewRerunPlanNotFoundError(azpErr.Message)
			}
		}
	case http.StatusTooManyRequests:
		err = new(azperrors.TooManyBuildsError)
	}

	if err == nil {
		retryable = false
		err = fmt.Errorf("unhandled error code %d", r.StatusCode)
	}

	return retryable, err
}

// urlCleaner matches tenant ID and job IDs as seen in many AZP urls looking like one of:
// aWAOBzblJsvoH2RohnNdEOEK0nyckHQ93Vp9CYTjnSe2ODQ000
// 05713c06-85ab-4551-ac28-46c3726e8000
var urlCleaner = regexp.MustCompile(`([a-zA-Z0-9]{50}|[a-z0-9-]{36})`)

func CleanRequestError(err error) error {
	errMessage := ""
	switch e := err.(type) {
	case *url.Error:
		// Only use the error message here, URL and Method are already added to fields
		errMessage = e.Err.Error()
	default:
		errMessage = err.Error()
	}

	errMessage = urlCleaner.ReplaceAllString(errMessage, "***")

	return fmt.Errorf("client.Do failed: %s", errMessage)
}
