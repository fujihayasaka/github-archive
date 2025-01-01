package types

import (
	"database/sql/driver"
	"fmt"
	"math"
	"strconv"
)

// Set of repository ids.
type RepoIDSet map[RepoID]bool

// A set of u32 ids.
type U32Set map[uint32]bool

// RepoID is a uint32 that represents a repository's unique ID.
// Repository owners and names may change, but RepoIDs stay the same.
type RepoID uint32

// Safely convert a RepoID to int32 (panics if this fails, in which case we need
// to update our protocol buffers to use a larger int)
func (r RepoID) ToInt32() int32 {
	if r > math.MaxInt32 {
		panic("time to update protos to uint32!")
	}

	return int32(r)
}

// RepoIDFromInt converts an int to a RepoID with bounds checking. Panics if this fails.
func RepoIDFromInt(id int) RepoID {
	if id < 0 || id > math.MaxUint32 {
		panic(fmt.Sprintf("invariant violated: tried to convert %d to RepoID", id))
	}

	return RepoID(id)
}

// RepoSeqNo represents the sequence of changes to a repository's metadata,
// and is used to compare repo metadata states between Blackbird's SnapshotEntries
// with dotcom's `repositories` table.
type RepoSeqNo uint64

// In error conditions in which it is not possible to identify the repo sequence number,
// this value is used as a sentinel value by the IndexQueryAPI to signal repo sequence number is unknown.
const UnknownRepoSeqNo = 0

// NetworkID is a uint32 that represents a repository's network ID.
// NOTE: Network IDs and Repository IDs are not comparable.
type NetworkID uint32

// A node in the MST holding a repository, any ancestors, and a preallocated
// child id to be used when constructing the delta encoding tree.
type RepoNode struct {
	RepoID              RepoID
	PreallocatedChildID uint32
	Ancestors           []RepoID
	MaxRepoScore        float32
	PartitionID         uint32
}

// Convert ancestors to a slice of uint32s.
func (n RepoNode) AncestorsUint32s() []uint32 {
	ancestorsUint32 := make([]uint32, 0, len(n.Ancestors))
	for _, ancestor := range n.Ancestors {
		ancestorsUint32 = append(ancestorsUint32, uint32(ancestor))
	}
	return ancestorsUint32
}

func PartitionID(repoID RepoID, partitions uint32) uint32 {
	return uint32(repoID) % partitions
}

// NullRepoID represents a RepoID that may be null. NullRepoID implements the
// Scanner interface so it can be used as a scan destination, similar to
// NullString.
type NullRepoID struct {
	RepoID RepoID
	Valid  bool
}

// Scan implements the Scanner interface.
func (n *NullRepoID) Scan(b interface{}) error {
	switch x := b.(type) {
	case nil:
		n.RepoID = RepoID(0)
		n.Valid = false
	case int64:
		if x < 0 || x > int64(math.MaxUint32) {
			return fmt.Errorf("value %d is too large to fit in uint32", x)
		}

		n.RepoID = RepoID(x)
		n.Valid = true
	case []byte:
		s := string(x)
		u64, err := strconv.ParseUint(s, 10, 32)
		if err != nil {
			return err
		}

		n.RepoID = RepoID(u64)
		n.Valid = true
	default:
		return fmt.Errorf("unsupported scan type %T: %+v", b, b)
	}

	return nil
}

// Value implements the driver Valuer interface.
func (n NullRepoID) Value() (driver.Value, error) {
	if !n.Valid {
		return nil, nil
	}
	return int64(n.RepoID), nil
}

// EpochID is the ID type for an index epoch.
type EpochID uint32

// Special value to represent any epoch in auto cluster selection.
const AnyEpoch EpochID = 0
