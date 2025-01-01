package twirp

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/hosted-compute-core/oidc"
	"github.com/github/hosted-compute-core/telemetry"
	jwtRequest "github.com/golang-jwt/jwt/v4/request"
	"github.com/twitchtv/twirp"
)

func validateAuthHandler(next http.Handler, hmacAuthAllowed, vssfAuthAllowed bool, authConfig *Config, vssfAuthClient oidc.IAuthService, logger *telemetry.ReportingLogger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var (
			hmacAuthStatus               bool = false
			vssfAuthStatus               bool = false
			hmacAuthError, vssfAuthError error
		)

		if hmacAuthAllowed {
			if authConfig.HmacAuthEnabled {
				hmacAuthStatus, hmacAuthError = validateHmacAuth(r, authConfig.HmacAuthVerifyKeys)
			} else {
				// if HMAC auth is disabled, consider auth as successful
				hmacAuthStatus = true
			}
		}

		// if HMAC auth is not enabled or HMAC header is not provided or HMAC is invalid, try vssf auth
		if !hmacAuthStatus && vssfAuthAllowed {
			if authConfig.VssfAuthEnabled {
				vssfAuthStatus, vssfAuthError = validateVssfAuth(r, vssfAuthClient)
			} else {
				// if Vssf auth is disabled, consider auth as successful
				vssfAuthStatus = true
			}
		}

		if !hmacAuthStatus && !vssfAuthStatus {
			var authError error
			if hmacAuthError != nil || vssfAuthError != nil {
				authError = twirp.NewError(twirp.Unauthenticated, errors.Join(hmacAuthError, vssfAuthError).Error())
			} else {
				authError = twirp.NewError(twirp.Unauthenticated, "unknown error")
			}
			logger.WithError(authError).Info("failed to authenticate request")
			if err := twirp.WriteError(w, authError); err != nil {
				logger.ErrorWithReport("failed to write response for unauthorized request", err)
			}
			return
		}

		next.ServeHTTP(w, r)
	})
}

func validateHmacAuth(req *http.Request, verifyKeys []string) (bool, error) {
	if len(verifyKeys) == 0 {
		return false, fmt.Errorf("no HMAC verify keys are defined")
	}

	hmacHeaderValue := req.Header.Get(headers.RequestHMAC)
	if hmacHeaderValue == "" {
		return false, fmt.Errorf("no Request-HMAC provided")
	}

	reqHMAC, err := hmac.ParseRequestHMAC(hmacHeaderValue)
	if err != nil {
		return false, fmt.Errorf("failed to parse request HMAC: %w", err)
	}

	for _, key := range verifyKeys {
		err = reqHMAC.Validate(key)
		if err == nil {
			return true, nil
		}
	}

	return false, err
}

func validateVssfAuth(req *http.Request, vssfAuthClient oidc.IAuthService) (bool, error) {
	token, err := jwtRequest.AuthorizationHeaderExtractor.ExtractToken(req)
	if err != nil {
		return false, fmt.Errorf("no bearer token provided")
	}

	_, err = vssfAuthClient.ValidateToken(token)
	if err != nil {
		return false, fmt.Errorf("failed to validate bearer token: %w", err)
	}

	return true, nil
}
