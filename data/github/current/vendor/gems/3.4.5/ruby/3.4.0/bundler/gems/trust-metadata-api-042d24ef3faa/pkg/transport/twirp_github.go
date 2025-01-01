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
func NewDotcomService(tma service.TMAService, cfg []auth.ClientConfig, opts ...TwirpServiceOption) (*TwirpService, error) {
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
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return 0, err
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return 0, ErrUnsupportedClient
	}

	// Get the owner ID, repository ID, and bundle from the request
	ownerID := req.GetOwnerId()
	repositoryID := req.GetRepositoryId()
	bundle := req.GetBundle()

	if ownerID <= 0 || repositoryID <= 0 {
		return 0, twirp.NewError(twirp.InvalidArgument, "owner_id and repository_id must be provided")
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

	identifiers.DomainID = client.DomainID
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
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId
	attestationID := req.AttestationId

	// Get the attestation record
	ar, err := ts.tma.GetAttestationByRepository(ctx, attestation.IdentifiersGitHub{
		DomainID:     client.DomainID,
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
				RunnerEnvironment: cs.Extensions.RunnerEnvironment,
				RepoVisibility:    cs.Extensions.SourceRepositoryVisibilityAtSigning,
				GitRef:            cs.Extensions.SourceRepositoryRef,
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
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("error getting current client: %w", err)
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID, repository ID, and attestation ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId
	attestationID := req.AttestationId

	// Get the attestation record
	ar, err := ts.tma.GetAttestationSummaryByRepository(ctx, attestation.IdentifiersGitHub{
		DomainID:     client.DomainID,
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
			Issuer:                              cs.Extensions.Issuer,
			BuildSignerUri:                      cs.Extensions.BuildSignerURI,
			BuildSignerDigest:                   cs.Extensions.BuildSignerDigest,
			RunnerEnvironment:                   cs.Extensions.RunnerEnvironment,
			SourceRepositoryUri:                 cs.Extensions.SourceRepositoryURI,
			SourceRepositoryDigest:              cs.Extensions.SourceRepositoryDigest,
			SourceRepositoryRef:                 cs.Extensions.SourceRepositoryRef,
			SourceRepositoryIdentifier:          cs.Extensions.SourceRepositoryIdentifier,
			SourceRepositoryOwnerUri:            cs.Extensions.SourceRepositoryOwnerURI,
			SourceRepositoryOwnerIdentifier:     cs.Extensions.SourceRepositoryOwnerIdentifier,
			BuildConfigUri:                      cs.Extensions.BuildConfigURI,
			BuildConfigDigest:                   cs.Extensions.BuildConfigDigest,
			BuildTrigger:                        cs.Extensions.BuildTrigger,
			RunInvocationUri:                    cs.Extensions.RunInvocationURI,
			SourceRepositoryVisibilityAtSigning: cs.Extensions.SourceRepositoryVisibilityAtSigning,
			SubjectAlternativeName: &rpc.SubjectAlternativeName{
				Value: cs.SubjectAlternativeName,
			},
		},
	}, nil
}

// ListAttestationSummariesByRepository retrieves a list summary of attestation records by owner and repository
func (ts *TwirpService) ListAttestationSummariesByRepository(ctx context.Context, req *rpc.ListAttestationsByRepositoryRequest) (*rpc.ListAttestationSummariesByRepositoryResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID and repository ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId

	if ownerID <= 0 || repositoryID <= 0 {
		return nil, twirp.NewError(twirp.InvalidArgument, "owner_id and repository_id must be provided")
	}

	// Check for optional filtering parameters
	predicateTypePattern, err := attestation.BuildPredicateTypePattern(req.GetPredicateType())
	if err != nil {
		return nil, ErrInvalidPredicateType
	}

	createdFilter, err := attestation.ValidateCreateArg(req.GetCreated())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	subjectName, err := attestation.ParseSubjectName(req.GetSubjectName())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursorFromRequest(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	identifiers := attestation.IdentifiersGitHub{
		Created:       createdFilter,
		DomainID:      client.DomainID,
		OwnerID:       &ownerID,
		PredicateType: predicateTypePattern,
		RepositoryID:  &repositoryID,
		SubjectName:   subjectName,
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	if attestationRecords == nil {
		return nil, ErrNoMatchingAttestations
	}
	if attestationRecords.PageInfo == nil {
		return nil, ErrNoMatchingAttestations
	}

	records := attestationRecords.Attestations
	if len(records) == 0 {
		return nil, ErrNoMatchingAttestations
	}

	if attestationRecords.PageInfo == nil {
		return nil, ErrNoMatchingAttestations
	}

	rpcPageInfo := &rpc.PageInfo{
		EndCursor:       attestationRecords.PageInfo.EndCursor,
		StartCursor:     attestationRecords.PageInfo.StartCursor,
		HasNextPage:     attestationRecords.PageInfo.HasNextPage,
		HasPreviousPage: attestationRecords.PageInfo.HasPreviousPage,
	}

	// map Records for response
	artifactAttestations := make([]*rpc.AttestationSummary, len(records))
	for i, ar := range records {
		// Create certificate summary for the response
		cs, err := certificate.SummarizeCertificate(ar.Certificate)
		if err != nil {
			return nil, err
		}

		artifactAttestations[i] = &rpc.AttestationSummary{
			Id:            ar.ID,
			OwnerId:       *ar.OwnerID,
			RepositoryId:  *ar.RepositoryID,
			PredicateType: ar.PredicateType,
			CreatedAt:     timestamppb.New(ar.CreatedAt),
			SubjectsCount: &ar.SubjectCount,
			CertificateSummary: &rpc.CertificateSummary{
				Issuer:                              cs.Extensions.Issuer,
				BuildSignerUri:                      cs.Extensions.BuildSignerURI,
				BuildSignerDigest:                   cs.Extensions.BuildSignerDigest,
				RunnerEnvironment:                   cs.Extensions.RunnerEnvironment,
				SourceRepositoryUri:                 cs.Extensions.SourceRepositoryURI,
				SourceRepositoryDigest:              cs.Extensions.SourceRepositoryDigest,
				SourceRepositoryRef:                 cs.Extensions.SourceRepositoryRef,
				SourceRepositoryIdentifier:          cs.Extensions.SourceRepositoryIdentifier,
				SourceRepositoryOwnerUri:            cs.Extensions.SourceRepositoryOwnerURI,
				SourceRepositoryOwnerIdentifier:     cs.Extensions.SourceRepositoryOwnerIdentifier,
				BuildConfigUri:                      cs.Extensions.BuildConfigURI,
				BuildConfigDigest:                   cs.Extensions.BuildConfigDigest,
				BuildTrigger:                        cs.Extensions.BuildTrigger,
				RunInvocationUri:                    cs.Extensions.RunInvocationURI,
				SourceRepositoryVisibilityAtSigning: cs.Extensions.SourceRepositoryVisibilityAtSigning,
				SubjectAlternativeName: &rpc.SubjectAlternativeName{
					Value: cs.SubjectAlternativeName,
				},
			},
		}
	}

	return &rpc.ListAttestationSummariesByRepositoryResponse{
		OwnerId:              ownerID,
		RepositoryId:         repositoryID,
		AttestationSummaries: artifactAttestations,
		PageInfo:             rpcPageInfo,
	}, nil
}

func (ts *TwirpService) buildListAttestationsBySubjectDigestIdentifiers(ctx context.Context, req *rpc.ListAttestationsBySubjectDigestRequest) (attestation.IdentifiersGitHub, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return attestation.IdentifiersGitHub{}, err
	}

	// Only GitHub/dotcom clients are supported for artifact attestations
	if !client.FromGitHub() {
		return attestation.IdentifiersGitHub{}, ErrUnsupportedClient
	}

	// Get the subject digest from the request for lookup
	subjectDigest := req.GetSubjectDigest()
	subjectDigestBatch := req.GetSubjectDigests()

	if subjectDigest == "" && subjectDigestBatch == nil {
		return attestation.IdentifiersGitHub{}, ErrNoSubjectDigest
	}

	if subjectDigest != "" && subjectDigestBatch != nil {
		return attestation.IdentifiersGitHub{}, ErrOnlyOneSubjectDigestArg
	}

	digestBatch, err := attestation.EnforceLength[string](subjectDigestBatch, "subject digests")
	if err != nil {
		return attestation.IdentifiersGitHub{}, ErrTooManySubjectDigests
	}

	pattern, err := attestation.BuildPredicateTypePattern(req.GetPredicateType())
	if err != nil {
		return attestation.IdentifiersGitHub{}, ErrInvalidPredicateType
	}

	return attestation.IdentifiersGitHub{
		DomainID:       client.DomainID,
		OwnerID:        &req.OwnerId,
		PredicateType:  pattern,
		RepositoryID:   req.RepositoryId,
		SubjectDigest:  subjectDigest,
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
	cursor, err := mysql.NewCursorFromRequest(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationsBySubjectDigest(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	if attestationRecords == nil {
		return nil, ErrNoMatchingAttestations
	}

	records := attestationRecords.Attestations
	if len(records) == 0 {
		return nil, ErrNoMatchingAttestations
	}

	if attestationRecords.PageInfo == nil {
		return nil, ErrNoMatchingAttestations
	}

	rpcPageInfo := &rpc.PageInfo{EndCursor: attestationRecords.PageInfo.EndCursor, StartCursor: attestationRecords.PageInfo.StartCursor, HasNextPage: attestationRecords.PageInfo.HasNextPage, HasPreviousPage: attestationRecords.PageInfo.HasPreviousPage}

	cc, ok := ctx.Value(CallerContextKeyName).(*CallerContext)
	if !ok {
		// Noting present, initialize a new empty
		cc = new(CallerContext)
	}

	// map Records to bundles
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
					RunnerEnvironment: cs.Extensions.RunnerEnvironment,
					RepoVisibility:    cs.Extensions.SourceRepositoryVisibilityAtSigning,
					GitRef:            cs.Extensions.SourceRepositoryRef,
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

/*
  GitHub API - Delete Routes
	  DELETE /twirp/github.trust_metadata_api.GitHubAPI/DeleteAttestationsByID
*/

// DeleteAttestationsByID deletes attestation records by their IDs
func (ts *TwirpService) DeleteAttestationsByID(ctx context.Context, req *rpc.DeleteAttestationsByIDRequest) (*rpc.DeleteAttestationsByIDResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only GitHub/dotcom clients are supported for artifact attestations
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	attestationIDs := req.GetAttestationIds()

	if len(attestationIDs) == 0 {
		return nil, ErrNoAttestationIDs
	}

	idBatch, err := attestation.EnforceLength[uint64](attestationIDs, "attestation ids")
	if err != nil {
		return nil, ErrTooManyAttestationIDs
	}

	// Delete attestation records
	if err := ts.tma.DeleteAttestationsByID(ctx, idBatch); err != nil {
		return nil, err
	}

	return &rpc.DeleteAttestationsByIDResponse{}, nil
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
