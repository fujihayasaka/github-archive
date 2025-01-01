package client

import (
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/pkg/errors"
)

var errorAttributeNotFound = errors.New("attribute not found")
var errorBadAttributeType = errors.New("attribute does not match the requested type")

// A AuthenticateResponse represents the outcome of an Authenticate request.
type AuthenticateResponse struct {
	// Result is the status code describing the outcome of the Authenticate request.
	//
	// RESULT_SUCCESS indicates a successful authentication, and that the Attributes field will contain attributes describing the authentication context.
	// Any other value indicates a failed authentication, and that the Attributes field will be empty.
	Result pb.AuthenticateResponse_Result

	// Attributes contains, for a successful result, the attributes describing the authentication context.
	//
	// Attributes can be nil, or have one of the following types:
	//
	// * `bool`
	// * `int64`
	// * `float64`
	// * `string`
	// * `[]int64`
	// * `[]string`
	// * `time.Time`
	Attributes map[string]interface{}
}

// Succeeded returns a boolean indicating if the result in this Response indicates success.
func (r *AuthenticateResponse) Succeeded() bool {
	return r.Result == pb.AuthenticateResponse_RESULT_SUCCESS
}

// GetBoolAttribute returns the value of a boolean attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `bool`
func (r *AuthenticateResponse) GetBoolAttribute(attributeName string) (bool, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return false, errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.(bool); ok {
		return t, nil
	}
	return false, errors.WithMessage(errorBadAttributeType, attributeName)
}

// GetIntAttribute returns the value of an integer attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `int64`
func (r *AuthenticateResponse) GetIntAttribute(attributeName string) (int64, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return 0, errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.(int64); ok {
		return t, nil
	}
	return 0, errors.WithMessage(errorBadAttributeType, attributeName)
}

// GetFloatAttribute returns the value of a float attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `float64`
func (r *AuthenticateResponse) GetFloatAttribute(attributeName string) (float64, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return 0, errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.(float64); ok {
		return t, nil
	}
	return 0, errors.WithMessage(errorBadAttributeType, attributeName)
}

// GetStringAttribute returns the value of a string attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `string`
func (r *AuthenticateResponse) GetStringAttribute(attributeName string) (string, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return "", errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.(string); ok {
		return t, nil
	}
	return "", errors.WithMessage(errorBadAttributeType, attributeName)
}

// GetIntegerListAttribute returns the value of an integer list attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `[]int64`
func (r *AuthenticateResponse) GetIntegerListAttribute(attributeName string) ([]int64, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return nil, errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.([]int64); ok {
		return t, nil
	}
	return nil, errors.WithMessage(errorBadAttributeType, attributeName)
}

// GetStringListAttribute returns the value of a string list attribute named `attributeName`
//
// Returns an error if the attribute doesn't exist, or if the attribute is not of type `[]string`
func (r *AuthenticateResponse) GetStringListAttribute(attributeName string) ([]string, error) {
	attribute, ok := r.Attributes[attributeName]
	if !ok {
		return nil, errors.WithMessage(errorAttributeNotFound, attributeName)
	}
	if t, ok := attribute.([]string); ok {
		return t, nil
	}
	return nil, errors.WithMessage(errorBadAttributeType, attributeName)
}

func responseFromTwirp(res *pb.AuthenticateResponse) (*AuthenticateResponse, error) {
	attributes, err := processTwirpAttributes(res.Attributes)
	if err != nil {
		return nil, err
	}
	return &AuthenticateResponse{
		Result:     res.Result,
		Attributes: attributes,
	}, nil
}

func processTwirpAttributes(twirpAttributes []*pb.Attribute) (map[string]interface{}, error) {
	unwrappedAttributes := make(map[string]interface{}, len(twirpAttributes))

	for _, attr := range twirpAttributes {
		attribute := attr.Value
		unwrappedAttribute, err := attribute.Unwrap()
		if err != nil {
			return nil, err
		}
		unwrappedAttributes[attr.Id] = unwrappedAttribute
	}

	return unwrappedAttributes, nil
}
