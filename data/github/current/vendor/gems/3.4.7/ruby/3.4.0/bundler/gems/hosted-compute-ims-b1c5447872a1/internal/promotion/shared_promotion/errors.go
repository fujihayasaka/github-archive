package shared_promotion

import (
	"strings"

	"github.com/github/hosted-compute-ims/internal/utils"
)

type PromotionError struct {
	Err              error
	UserErrorDetails string
	NonRetryable     bool
}

func (e *PromotionError) Error() string {
	return e.Err.Error()
}

func (e *PromotionError) UserError() string {
	return e.UserErrorDetails
}

func (e *PromotionError) IsSharedDevImagesError() bool {
	return strings.Contains(e.Err.Error(), utils.SharedDevImagesErrorMessage)
}
