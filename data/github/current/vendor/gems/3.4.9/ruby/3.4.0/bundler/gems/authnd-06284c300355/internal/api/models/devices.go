package models

import pb "github.com/github/authnd/client/proto/authentication/v0"

type RequestDeviceAuthResult int32

const (
	RequestDeviceAuthResult_Error RequestDeviceAuthResult = iota
	RequestDeviceAuthResult_Success
	RequestDeviceAuthResult_NoDevices
)

var RequestDeviceAuthResultMap = map[RequestDeviceAuthResult]pb.RequestDeviceAuthResponse_Result{
	RequestDeviceAuthResult_Success:   pb.RequestDeviceAuthResponse_RESULT_SUCCESS,
	RequestDeviceAuthResult_NoDevices: pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS,
	RequestDeviceAuthResult_Error:     pb.RequestDeviceAuthResponse_RESULT_FAILED_GENERIC,
}

type CompleteDeviceAuthType string

const (
	CompleteDeviceAuthType_Reject  CompleteDeviceAuthType = "reject"
	CompleteDeviceAuthType_Approve CompleteDeviceAuthType = "approve"
)

type CompleteDeviceAuthResult int32

const (
	CompleteDeviceAuthResult_Error CompleteDeviceAuthResult = iota
	CompleteDeviceAuthResult_Success
	CompleteDeviceAuthResult_NotFound
	CompleteDeviceAuthResult_NotActive
)

var CompleteDeviceAuthResultMap = map[CompleteDeviceAuthResult]pb.CompleteDeviceAuthResponse_Result{
	CompleteDeviceAuthResult_Success:   pb.CompleteDeviceAuthResponse_RESULT_SUCCESS,
	CompleteDeviceAuthResult_NotFound:  pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND,
	CompleteDeviceAuthResult_NotActive: pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE,
	CompleteDeviceAuthResult_Error:     pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC,
}
