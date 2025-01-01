package testhelpers

import (
	"fmt"
	"sync"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var (
	once       sync.Once
	testLogger = log.NewNullLogger()
)

func RequireEqualAttributeSlices(t *testing.T, x, y []*pb.Attribute, ignoreOrder bool) {
	require.Equal(t, len(x), len(y), fmt.Sprintf("expected: %v, actual: %v", x, y))

	for i := range x {
		xType := x[i].Value.GetKindName()

		var yAttr *pb.Attribute
		if ignoreOrder {
			yAttr = getAttributeById(y, x[i].GetId())
		} else {
			yAttr = y[i]
		}

		require.NotNil(t, yAttr)
		require.Equal(t, xType, yAttr.Value.GetKindName())

		xValue, err := x[i].Value.Unwrap()
		require.NoError(t, err)

		yValue, err := yAttr.Value.Unwrap()
		require.NoError(t, err)

		if xTime, ok := xValue.(*timestamppb.Timestamp); ok {
			// check that times differ by no more than 1ms
			yTime := yValue.(*timestamppb.Timestamp)
			require.InDelta(t, xTime.Nanos, yTime.Nanos, 1000, "pb times are not equal") // 1ms tolerance
		} else if xTime, ok := xValue.(time.Time); ok {
			// check that times differ by no more than 1s
			yTime := yValue.(time.Time)
			require.Equal(t, xTime.Truncate(time.Second), yTime.Truncate(time.Second), "times are not equal") // truncate nanoseconds
		} else {
			require.Equal(t, xValue, yValue, "values not equal")
		}
	}
}

func getAttributeById(attrs []*pb.Attribute, id string) *pb.Attribute {
	if attrs == nil {
		return nil
	}

	for _, attr := range attrs {
		if attr.Id == id {
			return attr
		}
	}
	return nil
}

func GetTestLogger() log.Logger {
	once.Do(func() {
		if testing.Verbose() {
			var err error
			testLogger, err = log.NewFromConfig(log.Config{
				LogLevel:           "debug",
				LogConsoleEncoding: "console",
			})
			if err != nil {
				panic(fmt.Sprintf("failed to construct test logger: %v", err))
			}
			testLogger.Debug("using debug logger")
		}
	})
	return testLogger
}

// small use of generics https://go.dev/blog/intro-generics#type-sets
type integer interface {
	~uint64 | ~int64 | ~int
}

func IntTokenClaim[I integer](v I) *uint64 {
	u := uint64(v)
	return &u
}

func StringTokenClaim(v string) *string {
	return &v
}
