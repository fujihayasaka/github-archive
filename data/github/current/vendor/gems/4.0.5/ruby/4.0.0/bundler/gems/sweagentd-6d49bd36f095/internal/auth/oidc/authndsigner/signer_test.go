package authndsigner

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/goerrors"
)

func TestSigner_IssueIDToken(t *testing.T) {
	t.Run("returns token on success", func(t *testing.T) {
		mockClient := authnd.NewNoopClient(1)
		mockClient.MockIssueIdentityToken = func(ctx context.Context, req authnd.IssueIdentityTokenRequest) (string, error) {
			return "signed-id-token", nil
		}
		signer := NewSignerWithClient(mockClient)

		token, err := signer.IssueIDToken(context.Background(), "https://example.com", "my-subject", "my-subject", nil)
		if err != nil {
			t.Fatalf("IssueIDToken() returned error: %v", err)
		}
		if token != "signed-id-token" {
			t.Errorf("IssueIDToken() = %q, want %q", token, "signed-id-token")
		}
	})

	t.Run("sends correct claims to authnd", func(t *testing.T) {
		var capturedReq authnd.IssueIdentityTokenRequest
		mockClient := authnd.NewNoopClient(1)
		mockClient.MockIssueIdentityToken = func(_ context.Context, req authnd.IssueIdentityTokenRequest) (string, error) {
			capturedReq = req
			return "tok", nil
		}
		signer := NewSignerWithClient(mockClient)

		_, err := signer.IssueIDToken(context.Background(), "aud-value", "sub-value", "act-sub-value", map[string]string{"repository": "owner/repo", "session_id": "123-123"})
		if err != nil {
			t.Fatalf("IssueIDToken() returned error: %v", err)
		}

		if capturedReq.Sub != "sub-value" {
			t.Errorf("Sub = %q, want %q", capturedReq.Sub, "sub-value")
		}
		if capturedReq.Aud != "aud-value" {
			t.Errorf("Aud = %q, want %q", capturedReq.Aud, "aud-value")
		}
		if capturedReq.Act.Sub != "act-sub-value" {
			t.Errorf("Act.Sub = %q, want %q", capturedReq.Act.Sub, "act-sub-value")
		}
		if capturedReq.AdditionalClaims["repository"] != "owner/repo" {
			t.Errorf("AdditionalClaims[repository] = %q, want %q", capturedReq.AdditionalClaims["repository"], "owner/repo")
		}
		if capturedReq.AdditionalClaims["session_id"] != "123-123" {
			t.Errorf("AdditionalClaims[session_id] = %q, want %q", capturedReq.AdditionalClaims["session_id"], "123-123")
		}
	})

	t.Run("accepts scope and resource claims", func(t *testing.T) {
		var capturedReq authnd.IssueIdentityTokenRequest
		mockClient := authnd.NewNoopClient(1)
		mockClient.MockIssueIdentityToken = func(_ context.Context, req authnd.IssueIdentityTokenRequest) (string, error) {
			capturedReq = req
			return "tok", nil
		}
		signer := NewSignerWithClient(mockClient)

		_, err := signer.IssueIDToken(context.Background(), "aud", "sub", "act-sub", map[string]string{
			"scope":    "read:org",
			"resource": "https://api.example.com",
		})
		if err != nil {
			t.Fatalf("IssueIDToken() returned error: %v", err)
		}
		if capturedReq.AdditionalClaims["scope"] != "read:org" {
			t.Errorf("AdditionalClaims[scope] = %q, want %q", capturedReq.AdditionalClaims["scope"], "read:org")
		}
		if capturedReq.AdditionalClaims["resource"] != "https://api.example.com" {
			t.Errorf("AdditionalClaims[resource] = %q, want %q", capturedReq.AdditionalClaims["resource"], "https://api.example.com")
		}
	})

	t.Run("rejects unknown claims", func(t *testing.T) {
		mockClient := authnd.NewNoopClient(1)
		signer := NewSignerWithClient(mockClient)

		_, err := signer.IssueIDToken(context.Background(), "aud", "sub", "sub", map[string]string{"forbidden_claim": "value"})
		if err == nil {
			t.Fatal("IssueIDToken() expected error for unknown claim, got nil")
		}
	})

	t.Run("errors when authnd client fails", func(t *testing.T) {
		mockClient := authnd.NewNoopClient(1)
		mockClient.MockIssueIdentityToken = func(_ context.Context, _ authnd.IssueIdentityTokenRequest) (string, error) {
			return "", goerrors.New("service unavailable")
		}
		signer := NewSignerWithClient(mockClient)

		_, err := signer.IssueIDToken(context.Background(), "aud", "sub", "sub", nil)
		if err == nil {
			t.Fatal("IssueIDToken() expected error when client fails, got nil")
		}
	})

	t.Run("errors when authnd returns empty token", func(t *testing.T) {
		mockClient := authnd.NewNoopClient(1)
		mockClient.MockIssueIdentityToken = func(_ context.Context, _ authnd.IssueIdentityTokenRequest) (string, error) {
			return "", nil
		}
		signer := NewSignerWithClient(mockClient)

		_, err := signer.IssueIDToken(context.Background(), "aud", "sub", "sub", nil)
		if err == nil {
			t.Fatal("IssueIDToken() expected error when token is empty, got nil")
		}
	})
}
