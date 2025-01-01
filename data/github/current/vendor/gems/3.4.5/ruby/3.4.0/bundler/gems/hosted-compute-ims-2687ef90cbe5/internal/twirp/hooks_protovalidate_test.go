package twirp

import (
	"context"
	"fmt"
	"testing"

	"entgo.io/ent/schema/field"
	"github.com/bufbuild/protovalidate-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type requestValidationTestCase struct {
	requestName   string
	testName      string
	request       field.Validator
	expectedError string
}

func (r *requestValidationTestCase) TestTitle() string {
	return fmt.Sprintf("%s - %s", r.requestName, r.testName)
}

func testProtoValidate(t *testing.T, test requestValidationTestCase) {
	t.Run(test.TestTitle(), func(t *testing.T) {
		ctx := context.Background()
		validator, err := protovalidate.New()
		require.NoError(t, err)

		mockNext := func(ctx context.Context, request interface{}) (interface{}, error) { return nil, nil }
		_, err = requestValidatorIntercepter(validator)(mockNext)(ctx, test.request)

		if test.expectedError != "" {
			assert.EqualError(t, err, test.expectedError)
		} else {
			assert.NoError(t, err)
		}
	})
}
