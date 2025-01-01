// THIS FILE WILL BE DELETED WHEN THE GLOBAL ID MIGRATION IS COMPLETE
// Tracking issue: https://github.com/github/c2c-actions-experience/issues/6576

package types

import (
	"context"
	"encoding/json"
	"fmt"
	"runtime"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/graphqlid"
)

var log logger.Logger

// NewGlobalID creates a global id from a string
// Use this function instead of a type conversion in non-test code until GitHub's global id migration is complete
func NewGlobalID(ctx context.Context, encoded string) GlobalID {
	gid := GlobalID(encoded)

	if err := gid.CheckFormat(); err != nil {
		// Log for now. After we're "clean", we'll switch to reporting an error to Sentry and panic.
		logWrongGIDFormat(ctx, err, encoded)
	}

	return gid
}

func IsZeroValueGlobalID(encoded string) bool {
	return encoded == string(NilGlobalID)
}

func IsNextGlobalID(encoded string) bool {
	return strings.Contains(encoded, "_")
}

func IsLegacyGlobalID(encoded string) bool {
	return strings.HasPrefix(encoded, "MD")
}

// IsConvertibleGlobalID returns true if the value is a legacy global id that can be converted to a next global id
func IsConvertibleGlobalID(encoded string) bool {
	if !IsLegacyGlobalID(encoded) || IsZeroValueGlobalID(encoded) || IsNextGlobalID(encoded) {
		return false
	}

	entityType, _, err := graphqlid.DecodeTypeIntID(encoded)
	if err != nil {
		return false
	}

	// Some entity types don't currently support the Next Global ID format
	if entityType == "IntegrationInstallation" {
		return false
	}

	return true
}

// UnmarshalJSON implements the Unmarshaler interface.
// This is used to log legacy global id uses in json payloads
func (g *GlobalID) UnmarshalJSON(bytes []byte) error {
	var val string
	err := json.Unmarshal(bytes, &val)
	if err != nil {
		*g = NilGlobalID
		return err
	}

	// Use NewGlobalID to log legacy global id uses
	*g = NewGlobalID(context.Background(), val)
	return nil
}

// Recommendation: If a violation can't be fixed within 24 hours, file a bug and add an exemption for two weeks.
var wrongGIDFormatFuncExemptions = map[string]time.Time{
	// This exclusion can be removed in December 2022, after database rows with legacy gids have aged out. See https://github.com/github/c2c-actions-experience/issues/6614
	"github.com/github/launch/types.(*GlobalID).Scan": time.Date(2022, time.December, 1, 0, 0, 0, 0, time.UTC),
}

var wrongGIDFormatCount uint64

func logWrongGIDFormat(ctx context.Context, formatErr error, encoded string) {
	if log == nil {
		log = logger.DefaultLogger()
	}

	defer func() {
		if r := recover(); r != nil {
			log.Error(ctx, "Recovered from panic in logWrongGIDFormat", kvp.Any("gh.launch.panic_recovery", r))
		}
	}()

	tempExemption := false
	var stack strings.Builder

	// construct the callstack and bail early on excluded functions
	for i := 1; i < 100; i++ {
		pc, file, line, ok := runtime.Caller(i)
		if !ok {
			break
		}

		details := runtime.FuncForPC(pc)
		funcName := "unknown"
		if details != nil {
			funcName = details.Name()
		}

		if expiration, ok := wrongGIDFormatFuncExemptions[funcName]; ok && time.Now().Before(expiration) {
			tempExemption = true
		}

		_, err := fmt.Fprintf(&stack, "%s:%d (%s)\n", file, line, funcName)
		if err != nil {
			log.ErrorWithFields(ctx, "Error writing to stack buffer", err)
			continue
		}
	}

	statter.DefaultStatter().Counter(ctx, "global_ids.wrong_format", statter.Tags{"temp_exemption": strconv.FormatBool(tempExemption)}, 1)

	// Only log the first 100k wrong global id formats to avoid spamming the logs prior to FFs being fully enabled
	if atomic.AddUint64(&wrongGIDFormatCount, 1) > 100000 {
		return
	}

	log.ErrorWithFields(ctx, "wrong global id format used", formatErr,
		kvp.String("gh.launch.global_id.encoded", encoded),
		kvp.String("exception_detail", stack.String()),
		kvp.Bool("gh.launch.temp_exemption", tempExemption),
	)
}
