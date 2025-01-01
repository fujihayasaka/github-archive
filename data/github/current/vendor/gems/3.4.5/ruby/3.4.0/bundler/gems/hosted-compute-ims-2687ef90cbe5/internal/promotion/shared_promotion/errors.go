package shared_promotion

import (
	"strings"

	"github.com/github/hosted-compute-ims/internal/utils"
)

// Ensure error meets the interface requirements for unwrapping (error.Is) and error.
var (
	_ error                       = (*PromotionError)(nil)
	_ interface{ Unwrap() error } = (*PromotionError)(nil)
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

// Unwrap is used to make it work with errors.Is, errors.As.
func (e *PromotionError) Unwrap() error {
	return e.Err
}
