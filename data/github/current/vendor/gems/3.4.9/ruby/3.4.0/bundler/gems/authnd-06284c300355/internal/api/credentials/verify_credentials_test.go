package credentials

import (
	"context"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVerifyPratV1Verified(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.True(t, resp.Responses[0].IsVerified)
	assert.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.ID), resp.Responses[0].CredentialId)
	assert.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.ActorID), resp.Responses[0].ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestVerifyPratV1Expired(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.ExpiredToken.Value),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.False(t, resp.Responses[0].IsVerified)
	assert.Zero(t, resp.Responses[0].CredentialId)
	assert.Zero(t, resp.Responses[0].ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_EXPIRED, resp.Responses[0].Result)
}

func TestVerifyPratV1NotFound(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.False(t, resp.Responses[0].IsVerified)
	assert.Zero(t, resp.Responses[0].CredentialId)
	assert.Zero(t, resp.Responses[0].ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_NOT_FOUND, resp.Responses[0].Result)
}

func TestVerifyUnsupportedCredentialType(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewSignedAuthTokenCredential(testfixtures.MonalisaValidSAT, "test"),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.False(t, resp.Responses[0].IsVerified)
	assert.Zero(t, resp.Responses[0].CredentialId)
	assert.Zero(t, resp.Responses[0].ActorId)
	assert.Contains(t, resp.Responses[0].Message, "unsupported credential type")
}

func TestVerifyInvalidFormat(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewAccessTokenCredential("invalid"),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.False(t, resp.Responses[0].IsVerified)
	assert.Zero(t, resp.Responses[0].CredentialId)
	assert.Zero(t, resp.Responses[0].ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Responses[0].Result)
}

func TestVerifyMixedResults(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := []*pb.Credentials{
		pb.NewAccessTokenCredential("invalid"),
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value),
		pb.NewAccessTokenCredential(testfixtures.ExpiredToken.Value),
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 4)

	actual := resp.Responses[0]
	assert.False(t, actual.IsVerified)
	assert.Zero(t, actual.CredentialId)
	assert.Zero(t, actual.ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Responses[0].Result)

	actual = resp.Responses[1]
	assert.True(t, actual.IsVerified)
	assert.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.ID), actual.CredentialId)
	assert.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.ActorID), actual.ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID), actual.AccessId)
	assert.Equal(t, testfixtures.MonalisaProgrammaticAccessToken.ExpiresAt.Time, actual.ExpiresAt.AsTime())

	actual = resp.Responses[2]
	assert.True(t, actual.IsVerified)
	assert.Equal(t, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID), actual.CredentialId)
	assert.Equal(t, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ActorID), actual.ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_SUCCESS, resp.Responses[2].Result)
	assert.Equal(t, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID), actual.AccessId)

	actual = resp.Responses[3]
	assert.False(t, actual.IsVerified)
	assert.Zero(t, actual.CredentialId)
	assert.Zero(t, actual.ActorId)
	assert.Equal(t, pb.VerifyResponse_RESULT_EXPIRED, resp.Responses[3].Result)
}

func TestVerifyExceedsMaxCandidates(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	candidates := make([]*pb.Credentials, 101)
	for i := 0; i < 101; i++ {
		candidates[i] = pb.NewAccessTokenCredential("invalid")
	}

	req := &pb.VerifyRequest{
		Candidates: candidates,
	}
	resp, err := c.VerifyCredentials(context.Background(), req)

	assert.Error(t, err)
	assert.Contains(t, err.Error(), "exceeded candidate limit")
	require.Nil(t, resp)
}
