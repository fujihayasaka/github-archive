package capi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
)

// ModelSessionRequest is the request body for creating a model session.
type ModelSessionRequest struct {
	AutoMode *ModelSessionAutoMode `json:"auto_mode"`
}

// ModelSessionAutoMode contains auto-mode specific parameters for a model session.
type ModelSessionAutoMode struct {
	ModelHints []string `json:"model_hints"`
}

// ModelSessionResponse is the response from the model session endpoint.
type ModelSessionResponse struct {
	AvailableModels []string           `json:"available_models"`
	SelectedModel   string             `json:"selected_model"`
	SessionToken    string             `json:"session_token"`
	ExpiresAt       int64              `json:"expires_at"`
	DiscountedCosts map[string]float64 `json:"discounted_costs,omitempty"`
}

// ModelSessionIntentRequest is the request body for the auto-intent ML routing
// endpoint (POST /models/session/intent). It refines the model choice within
// an existing CAPI auto-mode session, based on the user's prompt.
//
// See: https://github.com/github/auto-intent-service/blob/main/docs/integrators_onboarding.md
type ModelSessionIntentRequest struct {
	Prompt          string   `json:"prompt"`
	AvailableModels []string `json:"available_models"`
	HasImage        bool     `json:"has_image,omitempty"`
	RoutingMethod   string   `json:"routing_method,omitempty"`
	CopilotPlan     string   `json:"copilot_plan,omitempty"`
	StickyThreshold float64  `json:"sticky_threshold,omitempty"`
}

// ModelSessionIntentResponse is the response from POST /models/session/intent.
// Clients should use ChosenModel for the upcoming chat call and CandidateModels
// as the ordered fallback list, unless Fallback is true — in which case the
// caller should keep the model originally selected by /models/session.
type ModelSessionIntentResponse struct {
	PredictedLabel  string             `json:"predicted_label"`
	Confidence      float64            `json:"confidence"`
	LatencyMs       int                `json:"latency_ms"`
	ChosenModel     string             `json:"chosen_model"`
	CandidateModels []string           `json:"candidate_models"`
	Scores          map[string]float64 `json:"scores,omitempty"`
	StickyOverride  bool               `json:"sticky_override"`
	HydraScores     map[string]float64 `json:"hydra_scores,omitempty"`
	ChosenShortfall float64            `json:"chosen_shortfall,omitempty"`
	RoutingMethod   string             `json:"routing_method,omitempty"`
	Fallback        bool               `json:"fallback"`
	FallbackReason  string             `json:"fallback_reason,omitempty"`
}

// CreateModelSession creates a new model session via CAPI's POST /models/session endpoint.
// This is used to bind model requests as part of a CAPI "session", for billing and capacity benefits.
// If existingToken is non-empty it is sent as the Copilot-Session-Token header so
// CAPI can refresh an existing session instead of creating a new one.
func (c *HmacClient) CreateModelSession(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*ModelSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.CreateModelSession")
	defer span.End()

	u := c.baseURL
	u.Path = "/models/session"

	reqBody := ModelSessionRequest{
		AutoMode: &ModelSessionAutoMode{
			ModelHints: modelHints,
		},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal model session request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.String(), bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(GitHubUserIDHeader, fmt.Sprintf("%d", userID))

	if existingToken != "" {
		req.Header.Set("Copilot-Session-Token", existingToken)
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			return nil, goerrors.WithStack(joberrors.NewCAPIError(resp, "unexpected status code from /models/session endpoint"))
		}
		return nil, goerrors.WithStack(joberrors.NewCAPIError(resp, fmt.Sprintf("unexpected status code from /models/session endpoint, body: %s", string(body))))
	}

	var sessionResp ModelSessionResponse
	err = json.NewDecoder(resp.Body).Decode(&sessionResp)
	if err != nil {
		return nil, goerrors.Errorf("failed to decode model session response: %w", err)
	}

	return &sessionResp, nil
}

// CreateModelSessionIntent calls CAPI's POST /models/session/intent endpoint,
// which proxies to the auto-intent-service ML router. It refines the model
// choice within an existing CAPI auto-mode session based on the user's prompt.
//
// sessionToken must be the session_token previously returned by
// CreateModelSession; CAPI requires it on Copilot-Session-Token and validates
// the JWT before forwarding to the upstream router.
//
// Callers should inspect the response's Fallback field — when true, the
// routing decision is not actionable and callers should keep the model
// originally selected by /models/session.
func (c *HmacClient) CreateModelSessionIntent(ctx context.Context, userID uint64, sessionToken string, intentReq ModelSessionIntentRequest) (*ModelSessionIntentResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.CreateModelSessionIntent")
	defer span.End()

	if sessionToken == "" {
		return nil, goerrors.New("session token is required for /models/session/intent")
	}

	u := c.baseURL
	u.Path = "/models/session/intent"

	bodyBytes, err := json.Marshal(intentReq)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal model session intent request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.String(), bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(GitHubUserIDHeader, fmt.Sprintf("%d", userID))
	req.Header.Set("Copilot-Session-Token", sessionToken)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			return nil, goerrors.WithStack(joberrors.NewCAPIError(resp, "unexpected status code from /models/session/intent endpoint"))
		}
		return nil, goerrors.WithStack(joberrors.NewCAPIError(resp, fmt.Sprintf("unexpected status code from /models/session/intent endpoint, body: %s", string(body))))
	}

	var intentResp ModelSessionIntentResponse
	err = json.NewDecoder(resp.Body).Decode(&intentResp)
	if err != nil {
		return nil, goerrors.Errorf("failed to decode model session intent response: %w", err)
	}

	return &intentResp, nil
}
