package tester

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/google/go-github/github"
	"github.com/stretchr/testify/assert"
)

func TestPublicKeysTestSuccess(t *testing.T) {
	c := func(ctx context.Context, key *github.Key) (*github.Key, *github.Response, error) {
		resp := &http.Response{
			Status:     http.StatusText(http.StatusCreated),
			StatusCode: http.StatusCreated,
		}
		ghresp := &github.Response{Response: resp}
		id := int64(1)
		return &github.Key{
				Key:   key.Key,
				Title: key.Title,
				ID:    &id,
			},
			ghresp,
			nil
	}

	d := func(ctx context.Context, id int64) (*github.Response, error) {
		resp := &http.Response{
			Status:     http.StatusText(http.StatusOK),
			StatusCode: http.StatusOK,
		}
		ghresp := &github.Response{Response: resp}
		return ghresp, nil
	}

	firstAttempt := true
	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		if firstAttempt {
			firstAttempt = false
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: map[string]interface{}{
					client.ActorIDAttribute:        int64(testActorID),
					client.ActorTypeAttribute:      testActorType,
					client.CredentialTypeAttribute: client.CredentialTypeSSHPublicKey,
					client.CredentialIDAttribute:   int64(1),
				},
			}, nil
		} else {
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND,
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

	keyTest := &publicKeysTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		githubCreateFunc: c,
		githubDeleteFunc: d,
	}

	err = keyTest.Run(ctx)
	assert.Nil(t, err)
}

func TestPublicKeysTestBadRevokeTimeout(t *testing.T) {
	c := func(ctx context.Context, key *github.Key) (*github.Key, *github.Response, error) {
		resp := &http.Response{
			Status:     http.StatusText(http.StatusCreated),
			StatusCode: http.StatusCreated,
		}
		ghresp := &github.Response{Response: resp}
		id := int64(1)
		return &github.Key{
				Key:   key.Key,
				Title: key.Title,
				ID:    &id,
			},
			ghresp,
			nil
	}

	d := func(ctx context.Context, id int64) (*github.Response, error) {
		resp := &http.Response{
			Status:     http.StatusText(http.StatusOK),
			StatusCode: http.StatusOK,
		}
		ghresp := &github.Response{Response: resp}
		return ghresp, nil
	}

	firstAttempt := true
	a := func(*client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
		if firstAttempt {
			firstAttempt = false
			return &client.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: map[string]interface{}{
					client.ActorIDAttribute:        int64(testActorID),
					client.ActorTypeAttribute:      testActorType,
					client.CredentialTypeAttribute: client.CredentialTypeSSHPublicKey,
					client.CredentialIDAttribute:   int64(1),
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

	keyTest := &publicKeysTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return &mockAuthndClient{authFunc: a}, nil
		},
		githubCreateFunc: c,
		githubDeleteFunc: d,
	}

	err = keyTest.Run(ctx)
	assert.Equal(t, "max tries exhausted attempting request to authnd", err.Error())
}
