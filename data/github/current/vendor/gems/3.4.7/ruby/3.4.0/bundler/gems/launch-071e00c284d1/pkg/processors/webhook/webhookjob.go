package webhook

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

const (
	headerNotFoundTmpl = "%s header not found"
)

// Job is the shape of an aqueduct message
type Job struct {
	WebhookDeliveryID string           `json:"guid"`
	Event             string           `json:"event"`
	RawPayload        *json.RawMessage `json:"payload"`
	GitHubRequestID   string           `json:"github_request_id"`
	EnqueuedAt        int64            `json:"enqueued_at"`
	ActionsMeta       *ActionsMeta     `json:"actions_meta"`
	WebhookMetadata   *metadata        `json:"hook"`
	// Other fields: parent
}
type ActionsMeta struct {
	RerunInfo          *types.RerunInfo `json:"rerun_info"`
	EnableDebugLogging bool             `json:"enable_debug_logging"`
}

func (j *Job) RerunInfo() *types.RerunInfo {
	if j.ActionsMeta == nil {
		return nil
	}
	return j.ActionsMeta.RerunInfo
}

func (j *Job) JobIDs() *types.JobIDs {
	if j.ActionsMeta == nil || j.ActionsMeta.RerunInfo == nil {
		return nil
	}
	return &j.ActionsMeta.RerunInfo.JobIDs
}

// EnqueuedAtTime returns the time.Time from EnqueuedAt
func (j Job) EnqueuedAtTime() time.Time {
	sec := j.EnqueuedAt
	nsec := (sec % 1_000) * 1_000_000 // Convert milliseconds to nanoseconds
	sec /= 1_000

	return time.Unix(sec, nsec)
}

func (j *Job) EnableDebugLogging() bool {
	if j.ActionsMeta == nil {
		return false
	}
	return j.ActionsMeta.EnableDebugLogging
}

// GitHubTenant parses webhook metadata (i.e. webhook headers) to return a GitHubTenant
// The function no-ops if isMultiTenant is false. An error when header values are present
// but malformed.
func (j *Job) GitHubTenant(isMultiTenant bool) (ghtenant.GitHubTenant, error) {
	if !isMultiTenant {
		return ghtenant.GitHubTenant{}, nil
	}

	if j.WebhookMetadata == nil {
		return ghtenant.GitHubTenant{}, errors.New("Hook field is nil")
	}

	if len(j.WebhookMetadata.Headers) == 0 {
		return ghtenant.GitHubTenant{}, errors.New("Hook headers are empty")
	}

	gt := ghtenant.GitHubTenant{}

	var foundTenantIDHeader bool
	var foundTenantSlugHeader bool

	for _, header := range j.WebhookMetadata.Headers {
		if value, ok := header[ghtenant.GitHubTenantIDHeader]; ok {
			foundTenantIDHeader = true
			tenantID, err := ghtenant.ValidateTenantID(value)
			if err != nil {
				return ghtenant.GitHubTenant{}, fmt.Errorf("Error validing tenant id: %w", err)
			}

			gt.ID = tenantID
			continue
		}

		if value, ok := header[ghtenant.GitHubTenantHeader]; ok {
			foundTenantSlugHeader = true
			tenantSlug, err := ghtenant.ValidateTenantSlug(value)
			if err != nil {
				return ghtenant.GitHubTenant{}, fmt.Errorf("Error validing tenant slug: %w", err)
			}

			gt.Slug = tenantSlug
		}
	}

	if !foundTenantIDHeader {
		return ghtenant.GitHubTenant{}, fmt.Errorf(headerNotFoundTmpl, ghtenant.GitHubTenantIDHeader)
	}

	if !foundTenantSlugHeader {
		return ghtenant.GitHubTenant{}, fmt.Errorf(headerNotFoundTmpl, ghtenant.GitHubTenantHeader)
	}

	return gt, nil
}

// metadata contains data relating to the webhook published through Aqueduct
type metadata struct {
	Headers []header `json:"headers"`
}

// header is a header that would be published alongside the webhook
// each header is a map with a single key and value
// https://github.com/github/github/blob/1f67b4751ffc441da6ced425528ba37b286c1bd4/packages/webhooks/app/models/hook/event.rb#L297-L299
type header map[string]string
