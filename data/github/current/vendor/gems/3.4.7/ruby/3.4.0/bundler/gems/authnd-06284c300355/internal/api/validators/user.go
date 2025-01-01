package validators

import (
	pb "github.com/github/authnd/client/proto/authentication/v0"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/utils"
	"github.com/github/authnd/internal/common"
	commonModels "github.com/github/authnd/internal/common/models"
	"github.com/pkg/errors"
)

func validateUser(getUserFunc utils.AwaitUserValidationFunc) (*commonModels.User, error) {
	user, err := getUserFunc()
	if err != nil {
		if errors.Is(utils.UserValidationError_UserSuspended, err) {
			return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED}
		}
		if errors.Is(err, common.StoreErrUnsupported) {
			return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		}
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	}
	if user == nil {
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN}
	}
	return user, nil
}
