package agent

import (
	"strconv"
	"strings"
)

// JobID represents a parsed job ID with its associated owner and repository IDs.
type JobID struct {
	Owner int64
	Repo  int64
	Value string
}

// NewJobID parses the job ID and extracts the repository owner and
// repository IDs.
//
// The job ID is expected to be in the format "owner-repo-uuid".
// For example, 123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2 would yield
//   - Owner: 123456,
//   - Repo: 654321,
//   - Value: "123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2"
//
// HACK (colbylwilliams): This is temporary until I add an efficient GetJobByID
// method to the JobsStore interface.
func NewJobID(id string) (*JobID, error) {
	parts := strings.SplitN(id, "-", 3)
	if len(parts) < 3 {
		return nil, ErrInvalidJobIDFormat
	}

	ownerPart := parts[0]
	if ownerPart == "" {
		return nil, ErrInvalidJobIDFormat
	}
	ownerID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return nil, ErrInvalidJobIDOwner
	}

	repoPart := parts[1]
	if repoPart == "" {
		return nil, ErrInvalidJobIDFormat
	}
	repoID, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return nil, ErrInvalidJobIDRepo
	}

	return &JobID{
		Owner: ownerID,
		Repo:  repoID,
		Value: id,
	}, nil
}
