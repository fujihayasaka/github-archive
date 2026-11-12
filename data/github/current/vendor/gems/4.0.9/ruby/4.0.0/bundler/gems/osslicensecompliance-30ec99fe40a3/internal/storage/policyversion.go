package storage

import (
	"fmt"
	"time"
)

// PolicyVersion represents the last modified timestamps of the three policy blobs
// (enterprise, organization, repository) that comprise a complete policy. It is used
// to detect policy changes during PR check execution via optimistic locking.
type PolicyVersion struct {
	EnterpriseLastModified *time.Time
	OrgLastModified        *time.Time
	RepoLastModified       *time.Time
}

// Equals compares two PolicyVersion instances for equality.
// Two versions are equal if all three timestamps match (including nil values).
func (pv *PolicyVersion) Equals(other *PolicyVersion) bool {
	if pv == nil && other == nil {
		return true
	}
	if pv == nil || other == nil {
		return false
	}

	return timeEquals(pv.EnterpriseLastModified, other.EnterpriseLastModified) &&
		timeEquals(pv.OrgLastModified, other.OrgLastModified) &&
		timeEquals(pv.RepoLastModified, other.RepoLastModified)
}

// ChangedFields returns a human-readable string describing which policy levels changed
// between this version and another. Returns empty string if versions are equal.
func (pv *PolicyVersion) ChangedFields(other *PolicyVersion) string {
	if pv.Equals(other) {
		return ""
	}

	var changed []string
	if !timeEquals(pv.EnterpriseLastModified, other.EnterpriseLastModified) {
		changed = append(changed, "enterprise")
	}
	if !timeEquals(pv.OrgLastModified, other.OrgLastModified) {
		changed = append(changed, "organization")
	}
	if !timeEquals(pv.RepoLastModified, other.RepoLastModified) {
		changed = append(changed, "repository")
	}

	return fmt.Sprintf("%v", changed)
}

// timeEquals compares two time pointers for equality, handling nil cases.
func timeEquals(t1, t2 *time.Time) bool {
	if t1 == nil && t2 == nil {
		return true
	}
	if t1 == nil || t2 == nil {
		return false
	}
	return t1.Equal(*t2)
}
