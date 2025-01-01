package status

import (
	"time"
)

// Default artifact expiration (90 days) if not explicitly given
const NinetyDays = time.Hour * 24 * 90

func getArtifactExpiration(createdAt time.Time, expiresAt time.Time) time.Time {
	if !expiresAt.IsZero() {
		return expiresAt
	}
	return createdAt.Add(NinetyDays)
}
