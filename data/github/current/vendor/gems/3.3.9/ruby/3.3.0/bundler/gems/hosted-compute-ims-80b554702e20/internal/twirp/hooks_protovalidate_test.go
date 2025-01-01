package twirp

import (
	"context"
	"fmt"
	"testing"

	"entgo.io/ent/schema/field"
	"github.com/bufbuild/protovalidate-go"
	"github.com/github/github-telemetry-go/log"
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
		logger := log.NewNullLogger()
		ctx := context.Background()
		validator, err := protovalidate.New()
		require.NoError(t, err)

		mockNext := func(ctx context.Context, request interface{}) (interface{}, error) { return nil, nil }
		_, err = ProtoValidateIntercepter(validator, logger)(mockNext)(ctx, test.request)

		if test.expectedError != "" {
			assert.ErrorContains(t, err, test.expectedError)
		} else {
			assert.NoError(t, err)
		}
	})
}
