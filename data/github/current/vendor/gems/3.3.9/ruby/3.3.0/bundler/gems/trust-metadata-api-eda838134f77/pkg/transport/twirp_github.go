package transport

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
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
	service, err := newTwirpService(tma, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp service: %w", err)
	}

	server := rpc.NewGitHubAPIServer(service, service.hooks, twirp.WithServerJSONCamelCaseNames(true))
	service.PathPrefix = server.PathPrefix()
	service.Handler = server

	// If authentication is enabled, create the auth middleware and wrap the
	// Twirp server in it. This middleware validates the HMAC of incoming requests
	authMiddleware, err := auth.NewAuthenticationMiddleware(service.log, cfg)
	if err != nil {
		return nil, fmt.Errorf("setting up HMAC auth: %w", err)
	}

	service.Handler = authMiddleware(server)

	return service, nil
}

/*
  GitHub API - Create Routes
	  POST /twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository
*/

// CreateAttestationByOwnerRepository creates an attestation for a given artifact
func (ts *TwirpService) CreateAttestationByOwnerRepository(ctx context.Context, req *rpc.CreateAttestationByOwnerRepositoryRequest) (*rpc.CreateAttestationByOwnerRepositoryResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID, repository ID, and bundle from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId
	bundle := req.GetBundle()

	// cast tenantID from string to uint64
	tenantIDUint64 := uint64(0)
	if tenantID, ok := ctx.Value(service.TenantIDCtxKeyName).(string); ok {
		tenantIDUint64, err = strconv.ParseUint(tenantID, 10, 64)
		if err != nil {
			return nil, ts.logErr(ctx, err)
		}
	}

	// Create the attestation
	attestation, err := ts.tma.CreateAttestation(ctx, bundle, attestation.IdentifiersGitHub{
		DomainID:                  client.DomainID,
		OwnerID:                   &ownerID,
		RepositoryID:              &repositoryID,
		TenantID:                  tenantIDUint64,
		VerifyProvenanceStatement: true,
	})
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	// send the hydro message with go routine
	ts.hydroClient.SendCreateAttestationHydroMessage(ctx, bundle, ownerID, repositoryID, tenantIDUint64)

	return &rpc.CreateAttestationByOwnerRepositoryResponse{AttestationId: attestation.ID}, nil
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
		return nil, ts.logErr(ctx, err)
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
		return nil, ts.logErr(ctx, err)
	}

	// Create provenance summary for the response
	pbBundle, err := sgbundle.NewBundle(ar.Bundle)
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}
	ps, err := attestation.NewProvenanceSummary(ctx, pbBundle)
	if err != nil {
		return nil, ts.logErr(ctx, err)
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
		return nil, ts.logErr(ctx, fmt.Errorf("error getting current client: %w", err))
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
		var notFoundErr service.NotFoundError
		if errors.As(err, &notFoundErr) {
			return nil, ErrNoMatchingAttestations
		}
		ts.log.Error(fmt.Sprintf("error GetAttestationSummaryByRepository for attestation_id: %d", *repositoryID))
		return nil, ts.logErr(ctx, fmt.Errorf("error parsing attestation record"))
	}

	// Create certificate summary for the response
	if ar.Certificate == nil {
		ts.log.Error(fmt.Sprintf("certificate for attestation_id: %d is nil", *repositoryID))
		return nil, ts.logErr(ctx, fmt.Errorf("attestation record has no certificate, %w", err))
	}

	cs, err := certificate.SummarizeCertificate(ar.Certificate)
	if err != nil {
		return nil, ts.logErr(ctx, fmt.Errorf("error parsing certificate for attestation record, %w", err))
	}

	return &rpc.GetAttestationSummaryByRepositoryResponse{
		AttestationSummary: &rpc.AttestationSummary{
			Id:            attestationID,
			OwnerId:       *ownerID,
			RepositoryId:  *repositoryID,
			CreatedAt:     timestamppb.New(ar.CreatedAt),
			SubjectDigest: ar.SubjectDigest,
			SubjectName:   ar.SubjectName,
			PredicateType: ar.PredicateType,
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

// ListAttestationsByRepositorySummary retrieves a list summary of attestation records by owner and repository
// Deprecating in favor of ListAttestationSummariesByRepository
func (ts *TwirpService) ListAttestationsByRepositorySummary(ctx context.Context, req *rpc.ListAttestationsByRepositoryRequest) (*rpc.ListAttestationsByRepositorySummaryResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID and repository ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId

	if ownerID <= 0 || repositoryID <= 0 {
		return nil, ts.logErr(ctx, errors.New("owner_id and repository_id must be provided"))
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursorFromRequest(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	identifiers := attestation.IdentifiersGitHub{
		DomainID:     client.DomainID,
		RepositoryID: &repositoryID,
		OwnerID:      &ownerID,
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationsByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, ts.logErr(ctx, err)
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

	rpcPageInfo := &rpc.PageInfo{EndCursor: attestationRecords.PageInfo.EndCursor, StartCursor: attestationRecords.PageInfo.StartCursor, HasNextPage: attestationRecords.PageInfo.HasNextPage, HasPreviousPage: attestationRecords.PageInfo.HasPreviousPage}

	// map Records for response
	artifactAttestations := make([]*rpc.AttestationSummary, len(records))
	for i, ar := range records {
		// Create certificate summary for the response
		cs, err := certificate.SummarizeCertificate(ar.Certificate)
		if err != nil {
			return nil, ts.logErr(ctx, err)
		}

		artifactAttestations[i] = &rpc.AttestationSummary{
			Id:            ar.ID,
			OwnerId:       *ar.OwnerID,
			RepositoryId:  *ar.RepositoryID,
			SubjectDigest: ar.SubjectDigest,
			SubjectName:   ar.SubjectName,
			PredicateType: ar.PredicateType,
			CreatedAt:     timestamppb.New(ar.CreatedAt),
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

	return &rpc.ListAttestationsByRepositorySummaryResponse{
		OwnerId:              ownerID,
		RepositoryId:         repositoryID,
		AttestationSummaries: artifactAttestations,
		PageInfo:             rpcPageInfo,
	}, nil
}

// ListAttestationSummariesByRepository retrieves a list summary of attestation records by owner and repository
func (ts *TwirpService) ListAttestationSummariesByRepository(ctx context.Context, req *rpc.ListAttestationsByRepositoryRequest) (*rpc.ListAttestationSummariesByRepositoryResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	// Only GitHub clients are supported
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the owner ID and repository ID from the request
	ownerID := req.OwnerId
	repositoryID := req.RepositoryId

	if ownerID <= 0 || repositoryID <= 0 {
		return nil, ts.logErr(ctx, errors.New("owner_id and repository_id must be provided"))
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursorFromRequest(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	identifiers := attestation.IdentifiersGitHub{
		DomainID:     client.DomainID,
		RepositoryID: &repositoryID,
		OwnerID:      &ownerID,
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, ts.logErr(ctx, err)
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
			return nil, ts.logErr(ctx, err)
		}

		artifactAttestations[i] = &rpc.AttestationSummary{
			Id:            ar.ID,
			OwnerId:       *ar.OwnerID,
			RepositoryId:  *ar.RepositoryID,
			SubjectDigest: ar.SubjectDigest,
			SubjectName:   ar.SubjectName,
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

// ListAttestationsBySubjectDigest returns all attestation records for a given artifact
func (ts *TwirpService) ListAttestationsBySubjectDigest(ctx context.Context, req *rpc.ListAttestationsBySubjectDigestRequest) (*rpc.ListAttestationsBySubjectDigestResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	// Only GitHub/dotcom clients are supported for artifact attestations
	if !client.FromGitHub() {
		return nil, ErrUnsupportedClient
	}

	// Get the subject digest from the request for lookup
	subjectDigest := req.GetSubjectDigest()
	if subjectDigest == "" {
		return nil, ts.logErr(ctx, ErrNoSubjectDigest)
	}

	// Create a cursor from the request for pagination
	cursor, err := mysql.NewCursorFromRequest(req.GetPerPage(), req.GetAfter(), req.GetBefore())
	if err != nil {
		return nil, ts.logErr(ctx, err)
	}

	identifiers := attestation.IdentifiersGitHub{
		DomainID:      client.DomainID,
		SubjectDigest: subjectDigest,
		RepositoryID:  req.RepositoryId,
		OwnerID:       &req.OwnerId,
	}

	// Get the attestation records
	attestationRecords, err := ts.tma.ListAttestationsBySubjectDigest(ctx, identifiers, cursor)
	if err != nil {
		return nil, ts.logErr(ctx, err)
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
	}

	// TODO: map the repodId and ownerId to the response
	return &rpc.ListAttestationsBySubjectDigestResponse{Attestations: artifactAttestations, PageInfo: rpcPageInfo}, nil
}
