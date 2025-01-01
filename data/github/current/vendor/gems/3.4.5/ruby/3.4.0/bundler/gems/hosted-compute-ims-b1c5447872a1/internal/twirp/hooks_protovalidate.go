package twirp

import (
	"context"
	"reflect"

	"google.golang.org/protobuf/proto"

	"github.com/bufbuild/protovalidate-go"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/twitchtv/twirp"
)

func ProtoValidateIntercepter(validator *protovalidate.Validator, logger log.Logger) twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			if v, ok := req.(proto.Message); ok {
				err := validator.Validate(v)
				if err != nil {
					method, known := twirp.MethodName(ctx)
					if !known {
						method = "unknown method"
					}

					requestType := reflect.TypeOf(req)
					logger.Info("request has invalid argument",
						kvp.String("method", method),
						kvp.String("entity_type", requestType.String()),
						kvp.String("error", err.Error()),
					)

					return nil, twirp.InvalidArgument.Error(err.Error())
				}
			}

			return next(ctx, req)
		}
	}
}
