package models

import pb "github.com/github/authnd/client/proto/authentication/v0"

type RevokeResult int32

const (
	RevokeResult_Success RevokeResult = iota
	RevokeResult_NotFound
	RevokeResult_AlreadyRevoked
	RevokeResult_NotSupported
	RevokeResult_CredentialInvalid
	RevokeResult_Error
)

var RevokeResponseResultMap = map[RevokeResult]pb.RevokeResponse_Result{
	RevokeResult_Success:           pb.RevokeResponse_RESULT_SUCCESS,
	RevokeResult_NotFound:          pb.RevokeResponse_RESULT_NOT_FOUND,
	RevokeResult_AlreadyRevoked:    pb.RevokeResponse_RESULT_ALREADY_REVOKED,
	RevokeResult_NotSupported:      pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED,
	RevokeResult_CredentialInvalid: pb.RevokeResponse_RESULT_FAILED_CREDENTIAL_INVALID,
	RevokeResult_Error:             pb.RevokeResponse_RESULT_FAILED_GENERIC,
}
