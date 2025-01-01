package archive

import (
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func setBoolIfNotNil(b *bool) *wrapperspb.BoolValue {
	if b != nil {
		return &wrapperspb.BoolValue{
			Value: *b,
		}
	}
	return nil
}
func setStrIfNotNil(s *string) *wrapperspb.StringValue {
	if s != nil {
		return &wrapperspb.StringValue{
			Value: *s,
		}
	}
	return nil
}

func setInt64IfNotNil(i *int64) *wrapperspb.Int64Value {
	if i == nil {
		return nil
	}
	return wrapperspb.Int64(*i)
}

func toTimestamp(t time.Time) *timestamppb.Timestamp {
	if t.IsZero() {
		return nil
	}
	return timestamppb.New(t)
}
