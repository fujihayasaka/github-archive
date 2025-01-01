package telemetry

import (
	"context"
	"sync/atomic"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-exceptions"
)

var client atomic.Pointer[exceptions.Reporter]

func SetFailbotClient(value *exceptions.Reporter) {
	client.Store(value)
}

func GetFailbotClient() *exceptions.Reporter {
	value := client.Load()
	if value == nil {
		return exceptions.NullReporter
	}
	return value
}

// Report will report the error to the upstream exception reporting client if a reporting client is defined.
func Report(ctx context.Context, reportErr error, tags ...kvp.Field) error {

	// Unfortunately we have to do this because the go-exceptions package doesn't use kvp.Field types for its tags
	sTags := prepTags(tags...)

	err := GetFailbotClient().Report(ctx, reportErr, sTags)
	if err != nil {
		return err
	}

	return nil
}

func prepTags(tags ...kvp.Field) map[string]string {
	m := make(map[string]string)

	for _, tag := range tags {
		m[tag.Key] = tag.String
	}

	return m
}
