package types

import (
	"net"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewRequestContext(t *testing.T) {
	examples := []struct {
		name                    string
		reqCtx                  *RequestContext
		expectedQOS             RequestContext_QualityOfService
		expectedUserID          uint64
		expectedRealIP          string
		expectedReadUncommitted bool
		expectedPushState       []byte
	}{
		{
			name:           "only qos",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 0,
			expectedRealIP: "",
		},
		{
			name:           "qos and user id",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithUserID(123)),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 123,
			expectedRealIP: "",
		},
		{
			name:           "qos and ipv4",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithRealIPAddr("185.199.108.133")),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 0,
			expectedRealIP: "185.199.108.133",
		},
		{
			name:           "qos and ipv6",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithRealIPAddr("2606:50c0:8002::154")),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 0,
			expectedRealIP: "2606:50c0:8002::154",
		},
		{
			name:           "qos and parsed ipv4",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithRealIP(net.ParseIP("185.199.108.133"))),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 0,
			expectedRealIP: "185.199.108.133",
		},
		{
			name:           "qos and parsed ipv6",
			reqCtx:         NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithRealIP(net.ParseIP("2606:50c0:8002::154"))),
			expectedQOS:    RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID: 0,
			expectedRealIP: "2606:50c0:8002::154",
		},
		{
			name:                    "read uncommitted",
			reqCtx:                  NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithReadUncommitted()),
			expectedQOS:             RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedReadUncommitted: true,
		},
		{
			name:              "push state",
			reqCtx:            NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithPushState([]byte("push state"))),
			expectedQOS:       RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedPushState: []byte("push state"),
		},
		{
			name:                    "everything",
			reqCtx:                  NewRequestContext(RequestContext_QUALITY_OF_SERVICE_DELAYABLE, WithUserID(123), WithRealIPAddr("185.199.108.133"), WithReadUncommitted(), WithPushState([]byte("push state"))),
			expectedQOS:             RequestContext_QUALITY_OF_SERVICE_DELAYABLE,
			expectedUserID:          123,
			expectedRealIP:          "185.199.108.133",
			expectedReadUncommitted: true,
			expectedPushState:       []byte("push state"),
		},
	}

	for i := range examples {
		ex := examples[i]
		t.Run(ex.name, func(t *testing.T) {
			assert.Equal(t, ex.expectedQOS, ex.reqCtx.GetQualityOfService(), "QualityOfService")
			assert.Equal(t, ex.expectedUserID, ex.reqCtx.GetUserId(), "UserId")
			assert.Equal(t, ex.expectedRealIP, ex.reqCtx.GetRealIp(), "RealIp")
			assert.Equal(t, ex.expectedReadUncommitted, ex.reqCtx.GetReadUncommitted(), "ReadUncommitted")
			assert.Equal(t, ex.expectedPushState, ex.reqCtx.GetPushState(), "PushState")
		})
	}
}

func TestValidateRequestContext(t *testing.T) {
	validExamples := []struct {
		name   string
		reqCtx *RequestContext
	}{
		{
			name: "only has qos",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
			},
		},
		{
			name: "qos and user_id",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				UserId:           1234,
			},
		},
		{
			name: "qos and short ipv4",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "1.1.1.1",
			},
		},
		{
			name: "qos and long ipv4",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "254.254.254.254",
			},
		},
		{
			name: "qos and ipv6 example 1",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "fe80::1ccb:a60d:8f8:622",
			},
		},
		{
			name: "qos and ipv6 example 2",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "fe80::1",
			},
		},
		{
			name: "qos and ipv6 example 3",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "2606:50c0:8002::154",
			},
		},
	}

	for i := range validExamples {
		ex := validExamples[i]
		t.Run(ex.name, func(t *testing.T) {
			assert.NoError(t, ex.reqCtx.Validate())
			assert.NoError(t, ex.reqCtx.ValidatePreview())
		})
	}

	notValidExamples := []struct {
		name          string
		reqCtx        *RequestContext
		expectedError string
	}{
		{
			name:          "nil",
			reqCtx:        nil,
			expectedError: "twirp error invalid_argument: request_context.quality_of_service must be set",
		},
		{
			name:          "no qos",
			reqCtx:        &RequestContext{},
			expectedError: "twirp error invalid_argument: request_context.quality_of_service must be set",
		},
		{
			name: "unrecognized qos",
			reqCtx: &RequestContext{
				QualityOfService: 4,
			},
			expectedError: "twirp error invalid_argument: request_context.quality_of_service must be set",
		},
		{
			name: "qos and garbage ip address",
			reqCtx: &RequestContext{
				QualityOfService: RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
				RealIp:           "TODO",
			},
			expectedError: "twirp error invalid_argument: request_context.real_ip must be an IPv4 or IPv6 address",
		},
	}

	for i := range notValidExamples {
		ex := notValidExamples[i]
		t.Run(ex.name, func(t *testing.T) {
			// Expect no error from validation (yet).
			assert.NoError(t, ex.reqCtx.Validate())
			// Expect the error to come from ValidatePreview.
			assert.EqualError(t, ex.reqCtx.ValidatePreview(), ex.expectedError)
		})
	}
}
