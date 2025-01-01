package credentials

import (
	"context"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRevokeByCredentialsSuccessMaxBatchSize(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(100)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := make([]*pb.Credentials, 0, MaxRevokeBatchSize)
	for i := 0; i < MaxRevokeBatchSize; i++ {
		credentials = append(credentials, pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value))
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, MaxRevokeBatchSize)
	for i := 1; i < MaxRevokeBatchSize; i++ {
		// the authstore doesn't keep persist credential revocation, so each credential returns success
		assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[i].Result)
	}
}

func TestRevokeByCredentialsFailureMaxBatchSizeExceeded(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := make([]*pb.Credentials, 0, MaxRevokeBatchSize+1)
	for i := 0; i < MaxRevokeBatchSize+1; i++ {
		credentials = append(credentials, pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value))
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, MaxRevokeBatchSize+1)
	for i := 0; i < MaxRevokeBatchSize+1; i++ {
		assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MAX_BATCH_SIZE_EXCEEDED, resp.Responses[i].Result)
	}
}

func TestRevokeByCredentialsInvalidTokenFormat(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential("invalid"),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

func TestRevokeByCredentialsUnknownTokenType(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential("gha_1AAAAAAI0im3k9mu7LaCJ_qeLdjBWT3PTGX29CcwfMnkX4gWxQAgYSbKobe9cU5PEQH7VI7AX202ZtlwS"),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

// legacy PrAT tests
func TestRevokeLegacyPrATByCredentialsSuccess(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestRevokeLegacyPrATByCredentialsExpired(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestRevokeLegacyPrATByCredentialsAlreadyRevoked(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

func TestRevokeLegacyPrATByCredentialsNotFound(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.NotFoundLegacyProgramaticAccessTokenPlainText.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

func TestRevokeLegacyPrATByCredentialsMixedResults(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value), // success
		pb.NewAccessTokenCredential(testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value),  // already revoked
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),                                  // not found
		pb.NewAccessTokenCredential("invalid"),                                                         // general failure
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 4)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[3].Result)
}

func TestRevokeLegacyPrATByCredentialsMissingReason(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value),
		pb.NewAccessTokenCredential(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value),
	}

	req := &pb.RevokeRequest{
		Kind: &pb.RevokeRequest_ByCredential{
			// Reason is missing
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 2)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[1].Result)
}

// PrAT tests
func TestRevokePrATByCredentialsSuccess(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestRevokePrATByCredentialsExpired(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.ExpiredToken.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestRevokePrATByCredentialsAlreadyRevoked(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.RevokedToken.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

func TestRevokePrATByCredentialsNotFound(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[0].Result)
	assert.NotNil(t, resp.Responses[0].Message)
}

func TestRevokePrATByCredentialsMixedResults(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value), // success
		pb.NewAccessTokenCredential(testfixtures.RevokedToken.Value),   // already revoked
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),  // not found
		pb.NewAccessTokenCredential("invalid"),                         // general failure
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 4)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[3].Result)
}

func TestRevokePrATByCredentialsMissingReason(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),
		pb.NewAccessTokenCredential(testfixtures.ExpiredToken.Value),
	}

	req := &pb.RevokeRequest{
		Kind: &pb.RevokeRequest_ByCredential{
			// Reason is missing
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 2)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[1].Result)
}

func TestRevokeByCredentialsMixedTokenTypes(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(4)
	c := createTestCredentialManager(t, mockPublisher)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaV0TokenPlainText.Value),                       // general failure (invalid)
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value), // success
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),                                 // success
		pb.NewAccessTokenCredential(testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value),  // already revoked
		pb.NewAccessTokenCredential(testfixtures.NotFoundLegacyProgramaticAccessTokenPlainText.Value),  // not found
		pb.NewAccessTokenCredential(testfixtures.FutureExpiredToken.Value),                             // success
		pb.NewAccessTokenCredential("invalid"),                                                         // general failure
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 7)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[3].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[4].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[5].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[6].Result)
}

func TestRevokeByIdSuccess(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)
	c := createTestCredentialManager(t, mockPublisher)

	ids := []int64{
		int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
}

func TestRevokeByIdAlreadyRevoked(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	ids := []int64{
		int64(testfixtures.RevokedLegacyProgrammaticAccessToken.ID),
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[0].Result)
}

func TestRevokeByIdNotFound(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	ids := []int64{
		99999,
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[0].Result)
}

func TestRevokeByIdMixedResults(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(3)
	c := createTestCredentialManager(t, mockPublisher)

	ids := []int64{
		int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID), // success
		int64(testfixtures.ExpiredLegacyProgrammaticAccessToken.ID),  // success
		int64(testfixtures.ExpiredProgrammaticAccessToken.ID),        // success
		int64(testfixtures.RevokedLegacyProgrammaticAccessToken.ID),  // already revoked
		9999, // not found
	}

	req := &pb.RevokeRequest{
		Reason: "test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 5)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[3].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[4].Result)
}

func TestRevokeByIdMissingReason(t *testing.T) {
	c := createTestCredentialManager(t, nil)

	ids := []int64{
		int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID),
		int64(testfixtures.ExpiredProgrammaticAccessToken.ID),
	}

	req := &pb.RevokeRequest{
		// Reason is missing
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := c.RevokeCredentials(context.Background(), req)

	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 2)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MISSING_REASON, resp.Responses[1].Result)
}
