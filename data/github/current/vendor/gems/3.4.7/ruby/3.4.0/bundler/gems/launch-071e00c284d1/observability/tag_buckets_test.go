package observability

import (
	"encoding/base64"
	"fmt"
	"math/rand"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/github/launch/types"
)

func TestBucketGlobalID(t *testing.T) {
	t.Run("Basic test", func(tt *testing.T) {
		bucket := BucketGlobalID("MDEwOlJlcG9zaXRvcnkxMjM=")

		assert.Greater(tt, len(bucket), 0)

		bucketNum, err := strconv.Atoi(bucket)
		assert.Nil(tt, err)

		assert.GreaterOrEqual(tt, bucketNum, 0)
		assert.Less(tt, bucketNum, numberOfBuckets)
	})

	t.Run("Even distribution across buckets", func(tt *testing.T) {
		bucketCounts := map[string]int{}

		globalIDsToBucket := 50 * 1000

		// Ensure the test behavior is consistent.
		rand.Seed(42)

		for i := 0; i < globalIDsToBucket; i++ {
			globalIDDecoded := fmt.Sprintf("010:Repository%d", rand.Int63())
			globalID := types.GlobalID(base64.StdEncoding.EncodeToString([]byte(globalIDDecoded)))
			bucketId := BucketGlobalID(globalID)
			bucketCounts[bucketId]++
		}

		// Confirm every bucketId was returned at least once.
		assert.Len(tt, bucketCounts, numberOfBuckets, "GlobalIDs were distributed across %d buckets instead of %d buckets", len(bucketCounts), numberOfBuckets)

		// Confirm there's an even distribution across all buckets.
		maxBucketCount := int(1.01 * float64(globalIDsToBucket) / numberOfBuckets)

		for bucketId, count := range bucketCounts {
			assert.LessOrEqual(tt, count, maxBucketCount, "Bucket distribution is uneven. Too many GlobalIDs (%d%%) were distributed to the '%v' bucket.", 100*count/globalIDsToBucket, bucketId)
		}
	})
}
