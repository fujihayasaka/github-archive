package transport

import (
	"context"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/twitchtv/twirp"
)

// getDomainIDAndValidate retrieves the current client from the context and validates it.
// Return an error if the client is not from GitHub or return the client's DomainID.
func getDomainIDAndValidate(ctx context.Context) (uint32, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return 0, err
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return 0, ErrUnsupportedClient
	}

	return client.DomainID, nil
}

// validateOwnerAndRepoIDs checks if the provided ownerID and repositoryID are valid (greater than 0).
// Returns an error if either ID is invalid.
func validateOwnerAndRepoIDs(ownerID, repositoryID uint64) error {
	if ownerID <= 0 || repositoryID <= 0 {
		return twirp.NewError(twirp.InvalidArgument, "owner_id and repository_id must be provided")
	}
	return nil
}

// ValidateAttestationResults checks if the provided attestation records are valid.
// Returns an error if the records are nil, have no PageInfo, or contain no attestations.
func ValidateAttestationResults(attestationRecords *attestation.Records) error {
	if attestationRecords == nil ||
		attestationRecords.PageInfo == nil ||
		len(attestationRecords.Attestations) == 0 {
		return ErrNoMatchingAttestations
	}
	return nil
}

// EnforceAttestationIDLength checks if the number of attestation IDs provided is a valid length.
// Returns an error if the list is empty or contains too many IDs.
func EnforceAttestationIDLength(attestationIDs []uint64) ([]uint64, error) {
	if len(attestationIDs) == 0 {
		return nil, ErrNoAttestationIDs
	}

	validIDs, err := attestation.EnforceLength(attestationIDs, "attestation ids")
	if err != nil {
		return nil, ErrTooManyAttestationIDs
	}

	return validIDs, nil
}

// EnforceSubjectDigestsLength checks if the number of subject digests provided is a valid length.
// Returns an error if the list is empty or contains too many digests.
func EnforceSubjectDigestsLength(subjectDigests []string) ([]string, error) {
	if len(subjectDigests) == 0 {
		return nil, ErrNoSubjectDigests
	}

	validDigests, err := attestation.EnforceLength(subjectDigests, "subject digests")
	if err != nil {
		return nil, ErrTooManySubjectDigests
	}

	return validDigests, nil
}

// checkOptionalFilteringTypes validates and parses optional filtering parameters.
// Returns the parsed predicate type pattern, created filter, and subject name, or an error if any parameter is invalid.
func checkOptionalFilteringTypes(predicateType, created, subjectName string) (string, attestation.CreatedFilter, string, error) {
	predicateTypePattern, err := attestation.BuildPredicateTypePattern(predicateType)
	if err != nil {
		return "", attestation.CreatedFilter{}, "", ErrInvalidPredicateType
	}

	createdFilter, err := attestation.ValidateCreateArg(created)
	if err != nil {
		return "", attestation.CreatedFilter{}, "", twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	parsedSubjectName, err := attestation.ParseSubjectName(subjectName)
	if err != nil {
		return "", attestation.CreatedFilter{}, "", twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	return predicateTypePattern, createdFilter, parsedSubjectName, nil
}
