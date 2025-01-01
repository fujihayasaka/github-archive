package versioning

import (
	"fmt"

	"github.com/google/uuid"
)

type Version string

const (
	V2 Version = "v2"
	V3 Version = "v3"
)

// The projection version queried by the usage API.
const ActiveProjectionVersion_Api = V2

// NewTempVersion returns a temporary version that can be used for testing or other purposes.
func NewTempVersion() Version {
	return Version(fmt.Sprintf("temp_%s", uuid.NewString()[:6]))
}

func (v Version) String() string {
	return string(v)
}
