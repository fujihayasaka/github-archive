package twirp

import (
	"context"

	"google.golang.org/protobuf/proto"

	"github.com/bufbuild/protovalidate-go"
	"github.com/twitchtv/twirp"
)

func requestValidatorIntercepter(validator protovalidate.Validator) twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			if v, ok := req.(proto.Message); ok {
				err := validator.Validate(v)
				if err != nil {
					return nil, twirp.InvalidArgument.Error(err.Error())
				}
			}

			return next(ctx, req)
		}
	}
}
