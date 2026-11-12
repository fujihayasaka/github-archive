package storage

import "strings"

// NormalizeHeadRef returns the canonical fully-qualified form of a head ref.
//
// Empty in -> empty out (caller persists as NULL).
// Already starts with "refs/" -> returned unchanged.
// Otherwise -> "refs/heads/" prepended.
//
// No whitespace trimming, no case folding. The storage column is
// utf8mb4_general_ci (case-insensitive at the collation level), matching
// ds-api's branch_ref column.
func NormalizeHeadRef(ref string) string {
	if ref == "" {
		return ""
	}
	if strings.HasPrefix(ref, "refs/") {
		return ref
	}
	return "refs/heads/" + ref
}

// normalizeHeadRefToNullable normalizes a *string head ref for storage.
// nil in → nil out (persisted as NULL). Non-nil is normalized via NormalizeHeadRef;
// empty string after normalization becomes nil (NULL).
func normalizeHeadRefToNullable(ref *string) *string {
	if ref == nil {
		return nil
	}
	normalized := NormalizeHeadRef(*ref)
	if normalized == "" {
		return nil
	}
	return &normalized
}
