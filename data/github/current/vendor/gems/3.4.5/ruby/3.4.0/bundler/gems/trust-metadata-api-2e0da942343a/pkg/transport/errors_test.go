package transport

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

func TestGetTwirpError(t *testing.T) {
	cause := errors.New("1")

	internalError := service.NewInternalError(cause)
	twirpInternalError := getTwirpError(internalError)
	assert.ErrorIs(t, internalError, cause)
	assert.Equal(t, internalError.Error(), "InternalError: 1")
	assert.ErrorIs(t, twirpInternalError, cause)
	assert.ErrorIs(t, twirpInternalError, internalError)
	assert.Equal(t, twirpInternalError.Code(), twirp.Internal)
	assert.Equal(t, twirpInternalError.Error(), "twirp error internal: internal error")

	badRequestError := service.NewBadRequestError(cause)
	twirpBadRequestError := getTwirpError(badRequestError)
	assert.ErrorIs(t, badRequestError, cause)
	assert.Equal(t, badRequestError.Error(), "BadRequestError: 1")
	assert.ErrorIs(t, twirpBadRequestError, cause)
	assert.ErrorIs(t, twirpBadRequestError, badRequestError)
	assert.Equal(t, twirpBadRequestError.Code(), twirp.InvalidArgument)
	assert.Equal(t, twirpBadRequestError.Error(), "twirp error invalid_argument: 1")

	conflictError := service.NewConflictError(cause)
	twirpConflictError := getTwirpError(conflictError)
	assert.ErrorIs(t, conflictError, cause)
	assert.Equal(t, conflictError.Error(), "ConflictError: 1")
	assert.ErrorIs(t, twirpConflictError, cause)
	assert.ErrorIs(t, twirpConflictError, conflictError)
	assert.Equal(t, twirpConflictError.Code(), twirp.AlreadyExists)
	assert.Equal(t, twirpConflictError.Error(), "twirp error already_exists: 1")
}

func TestErrorInterceptorWithTwirpError(t *testing.T) {
	expectedErr := twirp.InternalError("test")
	method := func(_ context.Context, _ interface{}) (interface{}, error) {
		return nil, expectedErr
	}

	interceptor := translateServiceErrorInterceptor()
	_, err := interceptor(method)(context.Background(), nil)
	assert.Equal(t, expectedErr, err)
}

func TestErrorInterceptorWithServiceError(t *testing.T) {
	innerErr := service.NewBadRequestError(fmt.Errorf("test"))
	method := func(_ context.Context, _ interface{}) (interface{}, error) {
		return nil, innerErr
	}

	interceptor := translateServiceErrorInterceptor()
	_, err := interceptor(method)(context.Background(), nil)
	assert.NotEqual(t, innerErr, err)

	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		assert.Equal(t, twirp.ErrorCode("invalid_argument"), twirpErr.Code())
	} else {
		assert.Fail(t, "expected twirp error")
	}
}
func Test_innerError(t *testing.T) {
	type args struct {
		err error
	}
	tests := []struct {
		name string
		args args
		want string
	}{
		{
			name: "mysql.ErrGetRecord",
			args: args{twirp.InternalErrorWith(service.NewInternalError(&mysql.ErrGetRecord{}))},
			want: "mysql_read",
		},
		{
			name: "mysql.ErrStoreRecord",
			args: args{twirp.InternalErrorWith(service.NewInternalError(&mysql.ErrStoreRecord{}))},
			want: "mysql_write",
		},
		{
			name: "mysql.ErrConvertFromSQLC",
			args: args{service.NewInternalError(&mysql.ErrConvertFromSQLC{})},
			want: "sqlc_conversion",
		},
		{
			name: "mysql.ErrConvertToSQLC",
			args: args{service.NewInternalError(&mysql.ErrConvertToSQLC{})},
			want: "sqlc_conversion",
		},
		{
			name: "azureblob.ErrBlobDownloadFailed",
			args: args{service.NewInternalError(&azureblob.ErrBlobDownloadFailed{})},
			want: "blob_storage_download",
		},
		{
			name: "InternalError",
			args: args{service.NewInternalError(fmt.Errorf("some other error"))},
			want: "internal",
		},
		{
			name: "random error",
			args: args{fmt.Errorf("some other error")},
			want: "",
		},
		{
			name: "BadRequestError",
			args: args{service.NewBadRequestError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "ConflictError",
			args: args{service.NewConflictError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "NotFoundError",
			args: args{service.NewNotFoundError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "mysql.ErrStoreRecord",
			args: args{service.NewNotFoundError(&mysql.ErrStoreRecord{})},
			want: "",
		},
		{
			name: "mysql.ErrGetRecord",
			args: args{service.NewNotFoundError(&mysql.ErrGetRecord{})},
			want: "",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			errType, _ := innerError(tt.args.err)
			assert.Equal(t, tt.want, errType)
		})
	}
}
