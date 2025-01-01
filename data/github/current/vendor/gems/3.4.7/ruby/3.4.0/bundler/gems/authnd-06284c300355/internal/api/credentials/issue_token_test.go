package credentials

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// PrAT TOKEN TESTS

func TestErrorResultWithBadTokenType(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: "B1Token",
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_UNSUPPORTED_TOKEN_TYPE, resp.Result)
}

func TestErrorResultWithOldTokenType(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: "VOToken",
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_UNSUPPORTED_TOKEN_TYPE, resp.Result)
}

func TestErrorResultWithoutAccessID(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
}

func TestErrorResultWithMistypedAccessID(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 123),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewStringAttribute("access.id", "1234"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
}

func TestIssuePrATTokenSuccessful(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)

	c := createTestCredentialManager(t, mockPublisher)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewInt64Attribute("access.id", 1),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)
	assert.NotEmpty(t, resp.Token)
	assert.NotEmpty(t, resp.TokenId)
}

func TestErrorResultGivenMissingActorId(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewStringAttribute("actor.type", "User"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
	assert.Contains(t, resp.Error, "actor.id")
}

func TestErrorResultGivenMissingActorType(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
	assert.Contains(t, resp.Error, "actor.type")
}

func TestErrorResultGivenReservedAttributeCredentialId(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewInt64Attribute("credential.id", 1),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
	assert.Contains(t, resp.Error, "credential.id")
}

func TestErrorResultGivenReservedAttributeCredentialType(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewStringAttribute("credential.type", "something"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
	assert.Contains(t, resp.Error, "credential.type")
}

func TestIssuePrATTokenWithExpirationSuccessful(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)

	c := createTestCredentialManager(t, mockPublisher)
	req := &pb.IssueTokenRequest{
		Type:          pb.ProgrammaticAccessTokenType,
		ExpiresAtTime: timestamppb.New(time.Now()),
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewInt64Attribute("access.id", 12),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)
	assert.NotEmpty(t, resp.Token)
	assert.NotEmpty(t, resp.TokenId)
	assert.NotEmpty(t, resp.ExpiresAtTime)
}

func TestIssuePrATTokenWithNonPromotedAttributesSuccessful(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishEvent(gomock.Any(), gomock.Any()).Times(1)

	c := createTestCredentialManager(t, mockPublisher)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewInt64Attribute("access.id", 12),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewInt64Attribute("attr.int", 1),
			pb.NewStringAttribute("attr.string", "value1"),
			pb.NewDoubleAttribute("attr.double", 1.1),
			pb.NewBoolAttribute("attr.bool", true),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)
	assert.NotEmpty(t, resp.Token)
	assert.NotEmpty(t, resp.TokenId)
}

func TestErrorResultGivenDuplicateAttributeId(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", 12345),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewStringAttribute("actor.type", "Repo"),
		},
	}
	resp, err := c.IssueToken(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.IssueTokenResponse_RESULT_INVALID_ATTRIBUTES, resp.Result)
	assert.Contains(t, resp.Error, "actor.type")
}
