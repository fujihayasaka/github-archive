package transport

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/hydro"
	"github.com/github/trust-metadata-api/pkg/o11y"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

/*
  GitHub API Service
*/

// NewDotcomService creates and configures a TwirpService that can be mounted
// on a router and dispatch calls for the Dotcom rpc interface.
// This service is used for creating and reading attestations from GitHub.com
func NewDotcomService(tma *service.TMA, cfg []auth.ClientConfig, opts ...TwirpServiceOption) (*TwirpService, error) {
	twirpService, err := newTwirpService(tma, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp twirpService: %w", err)
	}

	server := rpc.NewGitHubAPIServer(twirpService,
		twirpService.hooks,
		twirp.WithServerInterceptors(twirpService.interceptors),
		twirp.WithServerJSONCamelCaseNames(true))
	twirpService.PathPrefix = server.PathPrefix()
	twirpService.Handler = server

	// If authentication is enabled, create the auth middleware and wrap the
	// Twirp server in it. This middleware validates the HMAC of incoming requests
	authMiddleware, err := auth.NewAuthenticationMiddleware(twirpService.log, cfg)
	if err != nil {
		return nil, fmt.Errorf("setting up HMAC auth: %w", err)
	}

	callerContextMiddleware := LogCallerContext(server)
	twirpService.Handler = authMiddleware(callerContextMiddleware)

	return twirpService, nil
}

/*
  GitHub API - Create Routes
	  POST /twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository
*/

// CreateAttestationByOwnerRepository creates an attestation for a given artifact
func (ts *TwirpService) CreateAttestationByOwnerRepository(ctx context.Context, req *rpc.CreateAttestationByOwnerRepositoryRequest) (*rpc.CreateAttestationByOwnerRepositoryResponse, error) {
	attestationID, err := ts.createAttestationByOwnerRepository(ctx, req, attestation.IdentifiersGitHub{})
	if err != nil {
		return nil, err
	}
	return &rpc.CreateAttestationByOwnerRepositoryResponse{AttestationId: attestationID}, err
}

// CreateReleaseAttestation create a release attestation
func (ts *TwirpService) CreateReleaseAttestation(ctx context.Context, req *rpc.CreateReleaseAttestationRequest) (*rpc.CreateReleaseAttestationResponse, error) {
	attestationID, err := ts.createAttestationByOwnerRepository(ctx, req, attestation.IdentifiersGitHub{
		ExpectReleaseAttestation: true,
	})
	if err != nil {
		return nil, err
	}
	return &rpc.CreateReleaseAttestationResponse{AttestationId: attestationID}, err
}

type createAttestationByOwnerRepositoryRequest interface {
	GetOwnerId() uint64
	GetRepositoryId() uint64
	GetBundle() *protobundle.Bundle
}

func (ts *TwirpService) createAttestationByOwnerRepository(ctx context.Context, req createAttestationByOwnerRepositoryRequest, identifiers attestation.IdentifiersGitHub) (uint64, error) {
	// Get the current client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return 0, err
	}

	// Get the owner ID, repository ID, and bundle from the request
	ownerID := req.GetOwnerId()
	repositoryID := req.GetRepositoryId()
	bundle := req.GetBundle()

	if err := validateOwnerAndRepoIDs(ownerID, repositoryID); err != nil {
		return 0, err
	}

	if bundle == nil {
		return 0, twirp.NewError(twirp.InvalidArgument, "bundle must be provided")
	}

	// cast tenantID from string to uint64
	tenantIDUint64 := uint64(0)
	if tenantID, ok := ctx.Value(o11y.TenantIDCtxKeyName).(string); ok {
		tenantIDUint64, err = strconv.ParseUint(tenantID, 10, 64)
		if err != nil {
			return 0, err
		}
	}

	identifiers.DomainID = clientDomainID
	identifiers.OwnerID = &ownerID
	identifiers.RepositoryID = &repositoryID
	identifiers.TenantID = tenantIDUint64

	// Create the attestation
	createdAttestation, err := ts.tma.CreateAttestation(ctx, bundle, identifiers)
	if err != nil {
		return 0, err
	}

	// send the hydro message with go routine
	ts.hydroClient.SendCreateAttestationHydroMessage(ctx, bundle, ownerID, repositoryID, tenantIDUint64)

	return createdAttestation.ID, nil
}

/*
  GitHub API - Read Routes
	  POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationByRepository
		POST /twirp/github.trust_metadata_api.GitHubAPI/GetAttestationSummaryByRepository
		POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsByRepository
		POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsByRepositorySummary
		POST /twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsBySubjectDigest
*/

// GetAttestationByRepository retrieves an attestation record by its ID
func (ts *TwirpService) GetAttestationByRepository(ctx context.Context, req *rpc.GetAttestationByRepositoryRequest) (*rpc.GetAttestationByRepositoryResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId
	attestationID := req.AttestationId

	// Get the attestation record
	ar, err := ts.tma.GetAttestationByRepository(ctx, attestation.IdentifiersGitHub{
		DomainID:     clientDomainID,
		ID:           attestationID,
		OwnerID:      ownerID,
		RepositoryID: repositoryID,
	})
	if err != nil {
		return nil, err
	}

	// Create provenance summary for the response
	pbBundle, err := sgbundle.NewBundle(ar.Bundle)
	if err != nil {
		return nil, err
	}
	ps, err := attestation.NewProvenanceSummary(ctx, pbBundle)
	if err != nil {
		return nil, err
	}

	if cs, err := certificate.SummarizeCertificate(ar.Certificate); err == nil {
		cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)

		if ok && cc.ActorID != 0 {
			hm := hydro.GetAttestationHydroMessage{
				TenantID:          ar.TenantID,
				OwnerID:           *ar.OwnerID,
				RepositoryID:      *ar.RepositoryID,
				ActorID:           cc.ActorID,
				InstallationID:    cc.InstallationID,
				SSIITargetID:      cc.SSIITargetID,
				SSIIRepositoryID:  cc.SSIIRepositoryID,
				PredicateType:     ar.PredicateType,
				CreatedAt:         ar.CreatedAt,
				RunnerEnvironment: cs.RunnerEnvironment,
				RepoVisibility:    cs.SourceRepositoryVisibilityAtSigning,
				GitRef:            cs.SourceRepositoryRef,
				SubjectsCount:     len(ar.Subjects),
			}

			ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
		}
	} else {
		ts.log.Warn("failed to summarize cert", kvp.Err(err))
	}

	return &rpc.GetAttestationByRepositoryResponse{
		Attestation: &rpc.ArtifactAttestation{
			Bundle:                   ar.Bundle,
			PredicateType:            ar.PredicateType,
			Id:                       ar.ID,
			OwnerId:                  *ar.OwnerID,
			RepositoryId:             *ar.RepositoryID,
			TenantId:                 ar.TenantID,
			SubjectDigest:            ar.SubjectDigest,
			CreatedAt:                timestamppb.New(ar.CreatedAt),
			SignedAccessSignatureUrl: ar.SASUrl,
		},
		ProvenanceSummary: &rpc.ProvenanceSummary{
			BuildTrigger:                      ps.BuildTrigger,
			SourceRepositoryDigest:            ps.SourceRepositoryDigest,
			SourceRepositoryRef:               ps.SourceRepositoryRef,
			RunInvocationUri:                  ps.RunInvocationURI,
			ResolvedSourceRepositoryCommitUri: ps.ResolvedSourceRepositoryCommitURI,
			BuildConfigDisplayName:            ps.BuildConfigDisplayName,
			ResolvedBuildConfigUri:            ps.ResolvedBuildConfigURI,
			ArtifactName:                      ps.ArtifactName,
		},
	}, nil
}

// GetAttestationSummaryByRepository returns summarized information about an attestation
func (ts *TwirpService) GetAttestationSummaryByRepository(ctx context.Context, req *rpc.GetAttestationSummaryByRepositoryRequest) (*rpc.GetAttestationSummaryByRepositoryResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, fmt.Errorf("error getting current client: %w", err)
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId
	attestationID := req.AttestationId

	// Get the attestation record
	ar, err := ts.tma.GetAttestationSummaryByRepository(ctx, attestation.IdentifiersGitHub{
		DomainID:     clientDomainID,
		ID:           attestationID,
		OwnerID:      ownerID,
		RepositoryID: repositoryID,
	})

	if err != nil {
		if errors.As(err, new(*service.NotFoundError)) {
			return nil, ErrNoMatchingAttestations
		}
		return nil, err
	}

	// Create certificate summary for the response
	if ar.Certificate == nil {
		return nil, fmt.Errorf("attestation record has no certificate, %w", err)
	}

	cs, err := certificate.SummarizeCertificate(ar.Certificate)
	if err != nil {
		return nil, fmt.Errorf("error parsing certificate for attestation record, %w", err)
	}

	return &rpc.GetAttestationSummaryByRepositoryResponse{
		AttestationSummary: &rpc.AttestationSummary{
			Id:            attestationID,
			OwnerId:       *ownerID,
			RepositoryId:  *repositoryID,
			CreatedAt:     timestamppb.New(ar.CreatedAt),
			PredicateType: ar.PredicateType,
			Subjects:      convertSubjects(ar.Subjects),
		},
		CertificateSummary: &rpc.CertificateSummary{
			Issuer:                              cs.Issuer,
			BuildSignerUri:                      cs.BuildSignerURI,
			BuildSignerDigest:                   cs.BuildSignerDigest,
			RunnerEnvironment:                   cs.RunnerEnvironment,
			SourceRepositoryUri:                 cs.SourceRepositoryURI,
			SourceRepositoryDigest:              cs.SourceRepositoryDigest,
			SourceRepositoryRef:                 cs.SourceRepositoryRef,
			SourceRepositoryIdentifier:          cs.SourceRepositoryIdentifier,
			SourceRepositoryOwnerUri:            cs.SourceRepositoryOwnerURI,
			SourceRepositoryOwnerIdentifier:     cs.SourceRepositoryOwnerIdentifier,
			BuildConfigUri:                      cs.BuildConfigURI,
			BuildConfigDigest:                   cs.BuildConfigDigest,
			BuildTrigger:                        cs.BuildTrigger,
			RunInvocationUri:                    cs.RunInvocationURI,
			SourceRepositoryVisibilityAtSigning: cs.SourceRepositoryVisibilityAtSigning,
			SubjectAlternativeName: &rpc.SubjectAlternativeName{
				Value: cs.SubjectAlternativeName,
			},
		},
	}, nil
}

// GetAttestationByRepository retrieves an attestation record by its ID
// nolint:revive
func (ts *TwirpService) GetBundlesById(ctx context.Context, req *rpc.GetBundlesByIdRequest) (*rpc.GetBundlesByIdResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	attestationIDs := req.AttestationIds
	if len(attestationIDs) == 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "attestation_ids must be provided")
	}
	ownerID := req.OwnerId
	if ownerID == 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id must be provided")
	}

	// Get the attestation record
	records, err := ts.tma.GetBundlesByID(ctx, attestation.IdentifiersGitHubGet{
		DomainID:       clientDomainID,
		AttestationIDs: attestationIDs,
		OwnerID:        ownerID,
	})
	if err != nil {
		return nil, err
	}

	rpcBundles := make([]*rpc.BundleById, len(records.Attestations))
	for i, a := range records.Attestations {
		cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
		if ok && cc.ActorID != 0 {
			hm := hydro.GetAttestationHydroMessage{
				OwnerID:      *a.OwnerID,
				RepositoryID: *a.RepositoryID,
			}
			ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
		}

		byId := &rpc.BundleById{
			Bundle:       a.Bundle,
			OwnerId:      *a.OwnerID,
			RepositoryId: *a.RepositoryID,
			Id:           a.ID,
		}
		rpcBundles[i] = byId
	}

	return &rpc.GetBundlesByIdResponse{
		Bundles: rpcBundles,
	}, nil
}

// GetRepositoryIdsByAttestationId retrieves a list of repository IDs by attestation ID
// nolint:revive
func (ts *TwirpService) GetRepositoryIdsByAttestationId(ctx context.Context, req *rpc.GetRepositoryIdsByAttestationIdRequest) (*rpc.GetRepositoryIdsByAttestationIdResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	idBatch, err := EnforceAttestationIDLength(req.AttestationIds)
	if err != nil {
		return nil, err
	}
	ownerID := req.OwnerId
	if ownerID == 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id must be provided")
	}

	// Get the attestation record
	records, err := ts.tma.GetRepoIDs(ctx, attestation.IdentifiersGitHubGet{
		DomainID:       clientDomainID,
		AttestationIDs: idBatch,
		OwnerID:        ownerID,
	})
	if err != nil {
		return nil, err
	}

	rpcRepos := make([]*rpc.RepoById, len(records))
	for i, r := range records {
		cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
		if ok && cc.ActorID != 0 {
			hm := hydro.GetAttestationHydroMessage{
				OwnerID:      *r.OwnerID,
				RepositoryID: *r.RepositoryID,
			}
			ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
		}

		byId := &rpc.RepoById{
			OwnerId:      *r.OwnerID,
			RepositoryId: *r.RepositoryID,
			Id:           r.ID,
		}
		rpcRepos[i] = byId
	}

	return &rpc.GetRepositoryIdsByAttestationIdResponse{
		Repos: rpcRepos,
	}, nil
}

// GetRepositoryIdsBySubjectDigest retrieves a list of repository IDs by subject digest
// nolint:revive
func (ts *TwirpService) GetRepositoryIdsBySubjectDigest(ctx context.Context, req *rpc.GetRepositoryIdsBySubjectDigestRequest) (*rpc.GetRepositoryIdsBySubjectDigestResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	digestBatch, err := EnforceSubjectDigestsLength(req.SubjectDigests)
	if err != nil {
		return nil, err
	}
	ownerID := req.OwnerId
	if ownerID == 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id must be provided")
	}

	// Get the attestation record
	records, err := ts.tma.GetRepoIDs(ctx, attestation.IdentifiersGitHubGet{
		DomainID:       clientDomainID,
		SubjectDigests: digestBatch,
		OwnerID:        ownerID,
	})
	if err != nil {
		return nil, err
	}

	rpcRepos := make([]*rpc.RepoByDigest, len(records))
	for i, r := range records {
		cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
		if ok && cc.ActorID != 0 {
			hm := hydro.GetAttestationHydroMessage{
				OwnerID:      *r.OwnerID,
				RepositoryID: *r.RepositoryID,
			}
			ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
		}

		byDigest := &rpc.RepoByDigest{
			OwnerId:       *r.OwnerID,
			RepositoryId:  *r.RepositoryID,
			SubjectDigest: r.SubjectDigest,
		}
		rpcRepos[i] = byDigest
	}

	return &rpc.GetRepositoryIdsBySubjectDigestResponse{
		Repos: rpcRepos,
	}, nil
}

// ListAttestationSummariesByRepository retrieves a list summary of attestation records by owner and repository
func (ts *TwirpService) ListAttestationSummariesByRepository(ctx context.Context, req *rpc.ListAttestationsByRepositoryRequest) (*rpc.ListAttestationSummariesByRepositoryResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	// Get the owner ID and repository ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId

	if err := validateOwnerAndRepoIDs(ownerID, repositoryID); err != nil {
		return nil, err
	}

	// Check for optional filtering parameters
	predicateTypePattern, createdFilter, subjectName, err := checkOptionalFilteringTypes(
		req.GetPredicateType(),
		req.GetCreated(),
		req.GetSubjectName())
	if err != nil {
		return nil, err
	}

	var sortOrder attestation.SortDirection
	switch req.GetDirection() {
	case rpc.SortDirection_SORT_DIRECTION_ASC:
		sortOrder = attestation.SortDirectionAsc
	case rpc.SortDirection_SORT_DIRECTION_DESC:
		sortOrder = attestation.SortDirectionDesc
	default:
		sortOrder = attestation.SortDirectionDesc
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursorWithCustomSort(sortOrder, req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	identifiers := attestation.IdentifiersGitHub{
		Created:       createdFilter,
		DomainID:      clientDomainID,
		OwnerID:       &ownerID,
		PredicateType: predicateTypePattern,
		RepositoryID:  &repositoryID,
		SubjectName:   subjectName,
	}

	// Get the attestation records
	records, err := ts.tma.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	if err := ValidateAttestationResults(records); err != nil {
		return nil, err
	}

	rpcPageInfo := &rpc.PageInfo{
		EndCursor:       records.PageInfo.EndCursor,
		StartCursor:     records.PageInfo.StartCursor,
		HasNextPage:     records.PageInfo.HasNextPage,
		HasPreviousPage: records.PageInfo.HasPreviousPage,
	}

	// map Records for response
	attestations := records.Attestations
	rpcSummaries := make([]*rpc.AttestationSummary, len(attestations))
	for i, ar := range attestations {
		// Create certificate summary for the response
		cs, err := certificate.SummarizeCertificate(ar.Certificate)
		if err != nil {
			return nil, err
		}

		rpcSummaries[i] = &rpc.AttestationSummary{
			Id:            ar.ID,
			OwnerId:       *ar.OwnerID,
			RepositoryId:  *ar.RepositoryID,
			PredicateType: ar.PredicateType,
			CreatedAt:     timestamppb.New(ar.CreatedAt),
			SubjectsCount: &ar.SubjectCount,
			Subjects:      convertSubjects(ar.Subjects),
			CertificateSummary: &rpc.CertificateSummary{
				Issuer:                              cs.Issuer,
				BuildSignerUri:                      cs.BuildSignerURI,
				BuildSignerDigest:                   cs.BuildSignerDigest,
				RunnerEnvironment:                   cs.RunnerEnvironment,
				SourceRepositoryUri:                 cs.SourceRepositoryURI,
				SourceRepositoryDigest:              cs.SourceRepositoryDigest,
				SourceRepositoryRef:                 cs.SourceRepositoryRef,
				SourceRepositoryIdentifier:          cs.SourceRepositoryIdentifier,
				SourceRepositoryOwnerUri:            cs.SourceRepositoryOwnerURI,
				SourceRepositoryOwnerIdentifier:     cs.SourceRepositoryOwnerIdentifier,
				BuildConfigUri:                      cs.BuildConfigURI,
				BuildConfigDigest:                   cs.BuildConfigDigest,
				BuildTrigger:                        cs.BuildTrigger,
				RunInvocationUri:                    cs.RunInvocationURI,
				SourceRepositoryVisibilityAtSigning: cs.SourceRepositoryVisibilityAtSigning,
				SubjectAlternativeName: &rpc.SubjectAlternativeName{
					Value: cs.SubjectAlternativeName,
				},
			},
		}
	}

	return &rpc.ListAttestationSummariesByRepositoryResponse{
		OwnerId:              ownerID,
		RepositoryId:         repositoryID,
		AttestationSummaries: rpcSummaries,
		PageInfo:             rpcPageInfo,
		TotalCount:           records.TotalCount,
	}, nil
}

func (ts *TwirpService) buildListAttestationsBySubjectDigestIdentifiers(ctx context.Context, req *rpc.ListAttestationsBySubjectDigestRequest) (attestation.IdentifiersGitHub, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return attestation.IdentifiersGitHub{}, err
	}

	pattern, err := attestation.BuildPredicateTypePattern(req.GetPredicateType())
	if err != nil {
		return attestation.IdentifiersGitHub{}, ErrInvalidPredicateType
	}

	// Get the subject digest from the request for lookup
	subjectDigest := req.GetSubjectDigest()
	subjectDigestBatch := req.GetSubjectDigests()

	if subjectDigest == "" && subjectDigestBatch == nil {
		return attestation.IdentifiersGitHub{}, ErrNoSubjectDigestArg
	}

	if subjectDigest != "" && subjectDigestBatch != nil {
		return attestation.IdentifiersGitHub{}, ErrOnlyOneSubjectDigestArg
	}

	// If a subject digest is provided, create identifiers with that
	if subjectDigest != "" {
		return attestation.IdentifiersGitHub{
			DomainID:      clientDomainID,
			OwnerID:       &req.OwnerId,
			PredicateType: pattern,
			RepositoryID:  req.RepositoryId,
			SubjectDigest: subjectDigest,
		}, nil
	}

	// Otherwise check if the subject digests follow length enforcement
	// and create identifiers with that
	digestBatch, err := EnforceSubjectDigestsLength(subjectDigestBatch)
	if err != nil {
		return attestation.IdentifiersGitHub{}, err
	}

	return attestation.IdentifiersGitHub{
		DomainID:       clientDomainID,
		OwnerID:        &req.OwnerId,
		PredicateType:  pattern,
		RepositoryID:   req.RepositoryId,
		SubjectDigests: digestBatch,
	}, nil
}

// ListAttestationsBySubjectDigest returns all attestation records for a given artifact
func (ts *TwirpService) ListAttestationsBySubjectDigest(ctx context.Context, req *rpc.ListAttestationsBySubjectDigestRequest) (*rpc.ListAttestationsBySubjectDigestResponse, error) {
	identifiers, err := ts.buildListAttestationsBySubjectDigestIdentifiers(ctx, req)
	if err != nil {
		return nil, err
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursor(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationsBySubjectDigest(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	if err := ValidateAttestationResults(attestationRecords); err != nil {
		return nil, err
	}

	rpcPageInfo := &rpc.PageInfo{EndCursor: attestationRecords.PageInfo.EndCursor, StartCursor: attestationRecords.PageInfo.StartCursor, HasNextPage: attestationRecords.PageInfo.HasNextPage, HasPreviousPage: attestationRecords.PageInfo.HasPreviousPage}

	cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
	if !ok {
		// Noting present, initialize a new empty
		cc = new(CallerContext)
	}

	// map Records to bundles
	records := attestationRecords.Attestations
	artifactAttestations := make([]*rpc.ArtifactAttestation, len(records))
	for i, ar := range records {
		artifactAttestations[i] = &rpc.ArtifactAttestation{
			Bundle:                   ar.Bundle,
			PredicateType:            ar.PredicateType,
			Id:                       ar.ID,
			OwnerId:                  *ar.OwnerID,
			TenantId:                 ar.TenantID,
			RepositoryId:             *ar.RepositoryID,
			SignedAccessSignatureUrl: ar.SASUrl,
			SubjectDigest:            ar.SubjectDigest,
		}

		if cc.ActorID != 0 {
			if cs, err := certificate.SummarizeCertificate(ar.Certificate); err == nil {
				hm := hydro.GetAttestationHydroMessage{
					TenantID:          ar.TenantID,
					OwnerID:           *ar.OwnerID,
					RepositoryID:      *ar.RepositoryID,
					ActorID:           cc.ActorID,
					InstallationID:    cc.InstallationID,
					SSIITargetID:      cc.SSIITargetID,
					SSIIRepositoryID:  cc.SSIIRepositoryID,
					PredicateType:     ar.PredicateType,
					CreatedAt:         ar.CreatedAt,
					RunnerEnvironment: cs.RunnerEnvironment,
					RepoVisibility:    cs.SourceRepositoryVisibilityAtSigning,
					GitRef:            cs.SourceRepositoryRef,
					SubjectsCount:     len(ar.Subjects),
				}

				ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
			} else {
				ts.log.Warn("failed to summarize cert", kvp.Err(err))
			}
		}
	}

	// TODO: map the repodId and ownerId to the response
	return &rpc.ListAttestationsBySubjectDigestResponse{Attestations: artifactAttestations, PageInfo: rpcPageInfo}, nil
}

// ListAttestationsBySubjectDigest returns all attestation records for a given artifact
func (ts *TwirpService) ListAttestationsBySubjectDigests(ctx context.Context, req *rpc.ListAttestationsBySubjectDigestsRequest) (*rpc.ListAttestationsBySubjectDigestsResponse, error) {
	domainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	predicateTypePattern, err := attestation.BuildPredicateTypePattern(req.GetPredicateType())
	if err != nil {
		return nil, ErrInvalidPredicateType
	}

	enforcedDigests, err := EnforceSubjectDigestsLength(req.GetSubjectDigests())
	if err != nil {
		return nil, err
	}

	identifiers := attestation.IdentifiersGitHub{
		DomainID:       domainID,
		OwnerID:        &req.OwnerId,
		PredicateType:  predicateTypePattern,
		RepositoryID:   req.RepositoryId,
		SubjectDigests: enforcedDigests,
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursor(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	// Get the attestation records
	recordsBySubjectDigest, err := ts.tma.ListAttestationsBySubjectDigests(ctx, identifiers, cursor)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch attestations: %w", err)
	}

	if len(recordsBySubjectDigest.RecordsWithSubjectDigest) == 0 {
		return nil, ErrNoMatchingAttestations
	}

	cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
	if !ok {
		// Noting present, initialize a new empty
		cc = new(CallerContext)
	}

	// map Records to bundles
	attestationsBySubjectDigest := []*rpc.AttestationsBySubjectDigest{}
	for _, collection := range recordsBySubjectDigest.RecordsWithSubjectDigest {
		entry := rpc.AttestationsBySubjectDigest{
			SubjectDigest: collection.SubjectDigest,
			Attestations:  []*rpc.ArtifactAttestation{},
		}
		for _, r := range collection.Attestations {
			aa := &rpc.ArtifactAttestation{
				SubjectDigest:            collection.SubjectDigest,
				Bundle:                   r.Bundle,
				PredicateType:            r.PredicateType,
				Id:                       r.ID,
				OwnerId:                  *r.OwnerID,
				TenantId:                 r.TenantID,
				RepositoryId:             *r.RepositoryID,
				SignedAccessSignatureUrl: r.SASUrl,
			}
			entry.Attestations = append(entry.Attestations, aa)
			if cc.ActorID != 0 {
				if cs, err := certificate.SummarizeCertificate(r.Certificate); err == nil {
					hm := hydro.GetAttestationHydroMessage{
						TenantID:          r.TenantID,
						OwnerID:           *r.OwnerID,
						RepositoryID:      *r.RepositoryID,
						ActorID:           cc.ActorID,
						InstallationID:    cc.InstallationID,
						SSIITargetID:      cc.SSIITargetID,
						SSIIRepositoryID:  cc.SSIIRepositoryID,
						PredicateType:     r.PredicateType,
						CreatedAt:         r.CreatedAt,
						RunnerEnvironment: cs.RunnerEnvironment,
						RepoVisibility:    cs.SourceRepositoryVisibilityAtSigning,
						GitRef:            cs.SourceRepositoryRef,
						SubjectsCount:     len(r.Subjects),
					}

					ts.hydroClient.SendGetAttestationHydroMessage(ctx, &hm)
				} else {
					ts.log.Warn("failed to summarize cert", kvp.Err(err))
				}
			}
		}
		attestationsBySubjectDigest = append(attestationsBySubjectDigest, &entry)
	}

	rpcPageInfo := &rpc.PageInfo{
		EndCursor:       recordsBySubjectDigest.PageInfo.EndCursor,
		StartCursor:     recordsBySubjectDigest.PageInfo.StartCursor,
		HasNextPage:     recordsBySubjectDigest.PageInfo.HasNextPage,
		HasPreviousPage: recordsBySubjectDigest.PageInfo.HasPreviousPage,
	}

	return &rpc.ListAttestationsBySubjectDigestsResponse{
		AttestationsBySubjectDigest: attestationsBySubjectDigest,
		OwnerId:                     req.OwnerId,
		PageInfo:                    rpcPageInfo,
		RepositoryId:                req.RepositoryId,
	}, nil
}

/*
  GitHub API - Delete Routes
	  DELETE /twirp/github.trust_metadata_api.GitHubAPI/DeleteAttestationsById
	  DELETE /twirp/github.trust_metadata_api.GitHubAPI/DeleteAttestationsBySubjectDigest
*/

// DeleteAttestationsByID deletes attestation records by their IDs
// nolint:revive // Twirp methods should treat abbreviations as single words
func (ts *TwirpService) DeleteAttestationsById(ctx context.Context, req *rpc.DeleteAttestationsByIdRequest) (*rpc.DeleteAttestationsByIdResponse, error) {
	// Get the current client and validate it is a GitHub client
	domainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	ownerID := req.GetOwnerId()
	if ownerID <= 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id must be provided")
	}
	// repositoryID is optional, so zero is a valid value
	var repoIDPtr *uint64
	repoID := req.GetRepositoryId()
	if repoID == 0 {
		repoIDPtr = nil
	} else {
		repoIDPtr = &repoID
	}

	idBatch, err := EnforceAttestationIDLength(req.GetAttestationIds())
	if err != nil {
		return nil, err
	}

	identifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       domainID,
		OwnerID:        ownerID,
		RepositoryID:   repoIDPtr,
		AttestationIDs: idBatch,
	}

	records, err := ts.tma.DeleteAttestationsByID(ctx, identifiers)
	if err != nil {
		if errors.As(err, new(*service.NotFoundError)) {
			return nil, ErrNoMatchingAttestations
		}
		return nil, err
	}

	cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
	if !ok {
		// Noting present, initialize a new empty
		cc = new(CallerContext)
	}

	for _, r := range records {
		hm := hydro.DeleteAttestationHydroMessage{
			TenantID:      r.TenantID,
			OwnerID:       *r.OwnerID,
			RepositoryID:  *r.RepositoryID,
			ActorID:       cc.ActorID,
			SubjectsCount: len(r.Subjects),
			Subjects:      r.Subjects,
		}

		ext, err := certificate.ParseExtensions(r.Certificate.Extensions)
		if err != nil {
			ts.log.Warn("failed to parse cert extensions", kvp.Err(err))
			ts.hydroClient.SendDeleteAttestationHydroMessage(ctx, &hm)
		} else {
			hm.RepoVisibility = ext.SourceRepositoryVisibilityAtSigning
			ts.hydroClient.SendDeleteAttestationHydroMessage(ctx, &hm)
		}
	}

	return &rpc.DeleteAttestationsByIdResponse{}, nil
}

// DeleteAttestationsByID deletes attestation records by subject digest
func (ts *TwirpService) DeleteAttestationsBySubjectDigest(ctx context.Context, req *rpc.DeleteAttestationsBySubjectDigestRequest) (*rpc.DeleteAttestationsBySubjectDigestResponse, error) {
	// Get the current client and validate it is a GitHub client
	clientDomainID, err := getDomainIDAndValidate(ctx)
	if err != nil {
		return nil, err
	}

	ownerID := req.GetOwnerId()
	if ownerID <= 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id must be provided")
	}
	// repositoryID is optional, so zero is a valid value
	var repoIDPtr *uint64
	repoID := req.GetRepositoryId()
	if repoID == 0 {
		repoIDPtr = nil
	} else {
		repoIDPtr = &repoID
	}

	digests, err := EnforceSubjectDigestsLength(req.GetSubjectDigests())
	if err != nil {
		return nil, err
	}

	identifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       clientDomainID,
		OwnerID:        ownerID,
		RepositoryID:   repoIDPtr,
		SubjectDigests: digests,
	}

	records, err := ts.tma.DeleteAttestationsBySubjectDigest(ctx, identifiers)
	if err != nil {
		if errors.As(err, new(*service.NotFoundError)) {
			return nil, ErrNoMatchingAttestations
		}
		return nil, err
	}

	cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
	if !ok {
		// Nothing present, initialize a new empty
		cc = new(CallerContext)
	}

	for _, r := range records {
		hm := hydro.DeleteAttestationHydroMessage{
			TenantID:      r.TenantID,
			OwnerID:       *r.OwnerID,
			RepositoryID:  *r.RepositoryID,
			ActorID:       cc.ActorID,
			SubjectsCount: len(r.Subjects),
			Subjects:      r.Subjects,
		}

		ext, err := certificate.ParseExtensions(r.Certificate.Extensions)
		if err != nil {
			ts.log.Warn("failed to parse cert extensions", kvp.Err(err))
			ts.hydroClient.SendDeleteAttestationHydroMessage(ctx, &hm)
		} else {
			hm.RepoVisibility = ext.SourceRepositoryVisibilityAtSigning
			ts.hydroClient.SendDeleteAttestationHydroMessage(ctx, &hm)
		}
	}

	return &rpc.DeleteAttestationsBySubjectDigestResponse{}, nil
}

/*
  Helper Functions
*/

// convertSubjects converts a slice of attestation.Subject to a slice of *rpc.Subject
func convertSubjects(subjects []attestation.Subject) []*rpc.Subject {
	rpcSubjects := make([]*rpc.Subject, len(subjects))
	for i, s := range subjects {
		rpcSubjects[i] = &rpc.Subject{
			SubjectName:   s.Name,
			SubjectDigest: s.Digest,
		}
	}

	return rpcSubjects
}
