package receiver

import (
	"fmt"
	"net/url"
	"time"
)

const (
	jobStatusCallbackURL      = `%s/actions/build/%s/jobs/{job_id}?timestamp=%s`
	runStatusCallbackURL      = `%s/actions/build/%s?timestamp=%s`
	gateStatusCallbackURL     = `%s/actions/build/%s/gates/{gate_id}?timestamp=%s`
	getEnvironmentCallbackURL = `%s/actions/build/%s/environments/{environment_name}?timestamp=%s`
	preJobRequestURL          = `%s/actions/build/%s/jobs/{job_id}/pre_job_tokens?timestamp=%s`
	tokenRefreshURL           = `%s/actions/build/%s/jobs/{job_id}/refresh_tokens?timestamp=%s`
	tokenRevokeURL            = `%s/actions/build/%s/jobs/{job_id}/revoke_tokens?timestamp=%s`
	actionsResolutionURL      = `%s/actions/build/%s/jobs/{job_id}/resolve/actions?timestamp=%s`
)

// GetJobStatusCallbackURL returns a URL template for AZP
func GetJobStatusCallbackURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the job status callback URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the job status callback URL cannot be empty")
	}
	u := fmt.Sprintf(jobStatusCallbackURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetRunStatusCallbackURL returns a URL template for AZP
func GetRunStatusCallbackURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the run status callback URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the run status callback URL cannot be empty")
	}
	u := fmt.Sprintf(runStatusCallbackURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetGateStatusCallbackURL returns a URL template for AZP
func GetGateStatusCallbackURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the gate status callback URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the gate status callback URL cannot be empty")
	}
	u := fmt.Sprintf(gateStatusCallbackURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetEnvironmentCallbackURL returns a URL template for AZP
func GetEnvironmentCallbackURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the get environment callback URL cannot be zero")
	}
	u := fmt.Sprintf(getEnvironmentCallbackURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetPreJobRequestURL returns a URL template for AZP
func GetPreJobRequestURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the token request URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the token request URL cannot be empty")
	}
	u := fmt.Sprintf(preJobRequestURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetTokenRefreshURL returns a URL template for AZP
func GetTokenRefreshURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the token request URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the token request URL cannot be empty")
	}
	u := fmt.Sprintf(tokenRefreshURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetTokenRevokeURL returns a URL template for AZP
func GetTokenRevokeURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the token request URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the token request URL cannot be empty")
	}
	u := fmt.Sprintf(tokenRevokeURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}

// GetActionResolutionURL returns a URL template for resolving an Action for
// Actions Servicer
func GetActionResolutionURL(receiverURL string, wfi string, timestamp time.Time) (string, error) {
	if timestamp.IsZero() {
		return "", fmt.Errorf("the timestamp for the action resolution callback URL cannot be zero")
	}
	if wfi == "" {
		return "", fmt.Errorf("the workflow id for the action resolution callback URL cannot be empty")
	}
	u := fmt.Sprintf(actionsResolutionURL, receiverURL, wfi, url.QueryEscape(timestamp.Format(time.RFC3339Nano)))
	if _, err := url.ParseRequestURI(u); err != nil {
		return "", err
	}
	return u, nil
}
