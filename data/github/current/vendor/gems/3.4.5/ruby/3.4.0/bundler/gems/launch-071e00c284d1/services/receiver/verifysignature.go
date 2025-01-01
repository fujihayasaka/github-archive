package receiver

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/go-chi/chi"
	errs "github.com/pkg/errors"

	"github.com/github/launch/services/auth/hkdf"
)

var authSignatureRegexp = regexp.MustCompile(`(?i)HMAC-SHA512 Signature=([A-Za-z0-9+/]+=*)$`)

// VerifySignature returns whether the request signature is valid or not, or an error
func VerifySignature(verifier hkdf.Verifier, req *http.Request, body []byte, receiverURL string) (bool, error) {
	authHeader := req.Header.Get("Authorization")
	if authHeader == "" {
		return false, errs.New("missing signature")
	}

	matches := authSignatureRegexp.FindStringSubmatch(authHeader)
	if len(matches) < 2 {
		return false, errs.New("no signature found in Authorization header")
	}
	sigString := matches[1]
	sig, err := base64.StdEncoding.DecodeString(sigString)
	if err != nil {
		return false, errs.Wrap(err, "invalid signature base64")
	}

	wfid := chi.URLParam(req, "workflowID")

	timestamp, err := GetTimestampFromRequest(req)
	if err != nil {
		return false, errs.Wrap(err, "could not parse time from timestamp parameter")
	}

	var sigBody strings.Builder
	sigBody.WriteString(fmt.Sprintf("%s%s", receiverURL, req.URL.RequestURI()))
	sigBody.WriteString("\n")
	sigBody.Write(body)

	isValid, err := verifier.Verify(wfid, timestamp, []byte(sigBody.String()), sig)
	if err != nil {
		return false, err
	}

	return isValid, nil
}

func GetTimestampFromRequest(req *http.Request) (time.Time, error) {
	timestampRaw, err := url.QueryUnescape(req.URL.Query().Get("timestamp"))
	if err != nil {
		return time.Time{}, errs.Wrap(err, "could not get timestamp from URL")
	}
	timestamp, err := time.Parse(time.RFC3339Nano, timestampRaw)
	if err != nil {
		return time.Time{}, err
	}
	return timestamp, nil
}
