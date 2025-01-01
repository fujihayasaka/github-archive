package tester

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/stretchr/testify/assert"
)

func TestProgrammaticAccessTokenTestSuccess(t *testing.T) {
	i := func(*pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
		return &pb.IssueTokenResponse{
			Result:  pb.IssueTokenResponse_RESULT_SUCCESS,
			Token:   "token",
			TokenId: 1,
		}, nil
	}

	r := func(*pb.RevokeRequest) (*pb.BatchRevokeResponse, error) {
		responses := make([]*pb.RevokeResponse, 1)
		responses[0] = &pb.RevokeResponse{
			Result: pb.RevokeResponse_RESULT_SUCCESS,
		}
		return &pb.BatchRevokeResponse{
			Responses: responses,
		}, nil
	}

	firstAttempt := true
	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		if firstAttempt {
			firstAttempt = false
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: map[string]interface{}{
					client.ActorIDAttribute:              int64(testActorID),
					client.ActorTypeAttribute:            testActorType,
					client.ProgrammaticAccessIDAttribute: int64(testAccessID),
					client.CredentialTypeAttribute:       pb.ProgrammaticAccessTokenType,
					client.CredentialIDAttribute:         int64(1),
				},
			}, nil
		} else {
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED,
			}, nil
		}
	}

	cfg, err := NewConfigFromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	ctx, err := cfg.NewRootContext()
	if err != nil {
		t.Fatal(err)
	}

	pratTest := &programmaticAccessTokenTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		credManagerFunc: func() (client.CredentialManager, error) {
			return &mockAuthndClient{issueFunc: i, revokeFunc: r}, nil
		},
	}

	err = pratTest.Run(ctx)
	assert.Nil(t, err)
}

func TestProgrammaticAccessTokenIssueHitsMaxAuthndAttempts(t *testing.T) {
	i := func(*pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
		return &pb.IssueTokenResponse{
			Result:  pb.IssueTokenResponse_RESULT_SUCCESS,
			Token:   "token",
			TokenId: 1,
		}, nil
	}

	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		return &client.AuthenticateResponse{
			Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
		}, nil
	}

	cfg, err := NewConfigFromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	ctx, err := cfg.NewRootContext()
	if err != nil {
		t.Fatal(err)
	}

	pratTest := &programmaticAccessTokenTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		credManagerFunc: func() (client.CredentialManager, error) {
			return &mockAuthndClient{issueFunc: i}, nil
		},
	}

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	err = pratTest.Run(ctx)
	assert.Equal(t, "max tries exhausted attempting request to authnd", err.Error())
}

func TestProgrammaticAccessTokenRevokeHitsMaxAuthndAttempts(t *testing.T) {
	i := func(*pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
		return &pb.IssueTokenResponse{
			Result:  pb.IssueTokenResponse_RESULT_SUCCESS,
			Token:   "token",
			TokenId: 1,
		}, nil
	}

	r := func(*pb.RevokeRequest) (*pb.BatchRevokeResponse, error) {
		responses := make([]*pb.RevokeResponse, 1)
		responses[0] = &pb.RevokeResponse{
			Result: pb.RevokeResponse_RESULT_SUCCESS,
		}
		return &pb.BatchRevokeResponse{
			Responses: responses,
		}, nil
	}

	// auth never returns revoked after revocation
	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		return &client.AuthenticateResponse{
			Result: pb.AuthenticateResponse_RESULT_SUCCESS,
			Attributes: map[string]interface{}{
				client.ActorIDAttribute:              int64(testActorID),
				client.ActorTypeAttribute:            testActorType,
				client.ProgrammaticAccessIDAttribute: int64(testAccessID),
				client.CredentialTypeAttribute:       pb.ProgrammaticAccessTokenType,
				client.CredentialIDAttribute:         int64(1),
			},
		}, nil
	}

	cfg, err := NewConfigFromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	ctx, err := cfg.NewRootContext()
	if err != nil {
		t.Fatal(err)
	}

	pratTest := &programmaticAccessTokenTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		credManagerFunc: func() (client.CredentialManager, error) {
			return &mockAuthndClient{issueFunc: i, revokeFunc: r}, nil
		},
	}

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	err = pratTest.Run(ctx)
	assert.Equal(t, "max tries exhausted attempting request to authnd", err.Error())
}

func TestProgrammaticAccessTokenLagTimesOutSafely(t *testing.T) {
	i := func(*pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
		return &pb.IssueTokenResponse{
			Result:  pb.IssueTokenResponse_RESULT_SUCCESS,
			Token:   "token",
			TokenId: 1,
		}, nil
	}

	r := func(*pb.RevokeRequest) (*pb.BatchRevokeResponse, error) {
		responses := make([]*pb.RevokeResponse, 1)
		responses[0] = &pb.RevokeResponse{
			Result: pb.RevokeResponse_RESULT_SUCCESS,
		}
		return &pb.BatchRevokeResponse{
			Responses: responses,
		}, nil
	}

	firstAttempt := true
	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		if firstAttempt {
			firstAttempt = false
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: map[string]interface{}{
					client.ActorIDAttribute:              int64(testActorID),
					client.ActorTypeAttribute:            testActorType,
					client.ProgrammaticAccessIDAttribute: int64(testAccessID),
					client.CredentialTypeAttribute:       pb.ProgrammaticAccessTokenType,
					client.CredentialIDAttribute:         int64(1),
				},
			}, nil
		} else {
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED,
			}, nil
		}
	}

	cfg, err := NewConfigFromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	ctx, err := cfg.NewRootContext()
	if err != nil {
		t.Fatal(err)
	}

	pratTest := &programmaticAccessTokenTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		credManagerFunc: func() (client.CredentialManager, error) {
			return &mockAuthndClient{issueFunc: i, revokeFunc: r}, nil
		},
	}

	// setting short context cancellation to trigger timeout before test can complete
	ctx, cancel := context.WithTimeout(ctx, 1*time.Microsecond)
	defer cancel()
	err = pratTest.Run(ctx)
	assert.Equal(t, "test execution exceeded timeout", err.Error())
}
