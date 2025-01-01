// Distributes unbounded identifiers across a small number of buckets so broad impact can be determined via metrics.
// We can use this to prevent errors limited to one or two repos from violating our SLO threshold, no matter the error volume.
// We can't add a `repo_global_id` tag to our metrics, but we can add a `repo_bucket` tag.
package observability

import (
	"hash/adler32"
	"strconv"

	"github.com/github/launch/types"
)

const numberOfBuckets = 3

// Returns a small bucket id for a GlobalID. This bucket id is suitable for tagging metrics.
func BucketGlobalID(globalID types.GlobalID) string {
	if len(globalID) < 1 {
		return "-1"
	}

	bucketNum := int(adler32.Checksum([]byte(globalID)) % numberOfBuckets)
	return strconv.Itoa(bucketNum)
}
