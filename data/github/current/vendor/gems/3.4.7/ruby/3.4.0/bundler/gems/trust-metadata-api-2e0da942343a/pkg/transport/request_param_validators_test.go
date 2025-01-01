package transport

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidateOwnerAndRepoIDs(t *testing.T) {
	err := validateOwnerAndRepoIDs(1, 1)
	assert.NoError(t, err)

	err = validateOwnerAndRepoIDs(0, 1)
	assert.Error(t, err)

	err = validateOwnerAndRepoIDs(1, 0)
	assert.Error(t, err)
}

func TestEnforceAttestationIDLength(t *testing.T) {
	ids := []uint64{1, 2, 3}
	validIDs, err := EnforceAttestationIDLength(ids)
	assert.NoError(t, err)
	assert.Equal(t, ids, validIDs)

	_, err = EnforceAttestationIDLength([]uint64{})
	assert.Error(t, err)
}

func TestEnforceSubjectDigestsLength(t *testing.T) {
	digests := []string{"digest1", "digest2"}
	validDigests, err := EnforceSubjectDigestsLength(digests)
	assert.NoError(t, err)
	assert.Equal(t, digests, validDigests)

	_, err = EnforceSubjectDigestsLength([]string{})
	assert.Error(t, err)
}
