package client

import (
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/twitchtv/twirp"

	"context"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/stretchr/testify/require"
	"testing"
)

type mockTwirpMobileDeviceManager struct {
	err            error
	Result         string
	OauthAccessIds []int64
}

func (m mockTwirpMobileDeviceManager) RevokeDeviceKeys(context.Context, *pb.RevokeDeviceKeysRequest) (*pb.RevokeDeviceKeysResponse, error) {
	if m.err != nil {
		return &pb.RevokeDeviceKeysResponse{Result: pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC}, m.err
	}
	return &pb.RevokeDeviceKeysResponse{Result: pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, OauthAccessIds: m.OauthAccessIds}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) RegisterDeviceKey(context.Context, *pb.RegisterDeviceKeyRequest) (*pb.RegisterDeviceKeyResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.RegisterDeviceKeyResponse{Result: pb.RegisterDeviceKeyResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) RevokeDeviceKey(context.Context, *pb.RevokeDeviceKeyRequest) (*pb.RevokeDeviceKeyResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.RevokeDeviceKeyResponse{Result: pb.RevokeDeviceKeyResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) FindDeviceKeyRegistrations(context.Context, *pb.FindDeviceKeyRegistrationsRequest) (*pb.FindDeviceKeyRegistrationsResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.FindDeviceKeyRegistrationsResponse{Result: pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) FindDeviceKeyRegistration(context.Context, *pb.FindDeviceKeyRegistrationRequest) (*pb.FindDeviceKeyRegistrationResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.FindDeviceKeyRegistrationResponse{Result: pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) RequestDeviceAuth(context.Context, *pb.RequestDeviceAuthRequest) (*pb.RequestDeviceAuthResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.RequestDeviceAuthResponse{Result: pb.RequestDeviceAuthResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) GetDeviceAuthStatus(context.Context, *pb.GetDeviceAuthStatusRequest) (*pb.GetDeviceAuthStatusResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.GetDeviceAuthStatusResponse{Result: pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) FindActiveDeviceAuth(context.Context, *pb.FindActiveDeviceAuthRequest) (*pb.FindActiveDeviceAuthResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.FindActiveDeviceAuthResponse{Result: pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS}, nil
}

// Have not implemented tests for the following method
func (m mockTwirpMobileDeviceManager) CompleteDeviceAuth(context.Context, *pb.CompleteDeviceAuthRequest) (*pb.CompleteDeviceAuthResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.CompleteDeviceAuthResponse{Result: pb.CompleteDeviceAuthResponse_RESULT_SUCCESS}, nil
}

func TestNewMobileDeviceManagerWithEmptyAddr(t *testing.T) {
	_, err := NewMobileDeviceManager("", "test")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty addr", err.Error())
}

func TestNewMobileDeviceManagerWithEmptyService(t *testing.T) {
	_, err := NewMobileDeviceManager("localhost.test", "")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty catalogService", err.Error())
}

func TestRevokeDeviceKeysOnSuccess(t *testing.T) {
	oauthIds := []int64{1, 2, 3}
	mockTwirpMobileDeviceManager := &mockTwirpMobileDeviceManager{
		Result:         "RESULT_SUCCESS",
		OauthAccessIds: oauthIds,
		err:            nil,
	}

	expectedTags := stats.Tags{
		"method": "RevokeDeviceKeys",
		"result": "RESULT_SUCCESS",
	}

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	mobileDeviceManager := &mobileDeviceManager{
		mockTwirpMobileDeviceManager,
		&mockStatter,
	}

	request := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: 123,
			},
		},
	}

	response, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), request)

	require.NoError(t, err)
	require.NotNil(t, response)
	require.Equal(t, response.Result, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS)
}

func TestRevokeDeviceKeysOnFailure(t *testing.T) {
	mockTwirpMobileDeviceManager := &mockTwirpMobileDeviceManager{
		Result: "RESULT_FAILED_GENERIC",
		err:    twirp.RequiredArgumentError("UserId"),
	}

	expectedTags := stats.Tags{
		"method": "RevokeDeviceKeys",
		"result": "twirp_client_error",
	}

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	mobileDeviceManager := &mobileDeviceManager{
		mockTwirpMobileDeviceManager,
		&mockStatter,
	}

	request := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: 0,
			},
		},
	}

	response, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), request)

	require.Error(t, err)
	require.Nil(t, response)
}
