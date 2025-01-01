package transport

import (
	"context"
	"fmt"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/package-url/packageurl-go"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

/*
  NPM API Services
	  PackageInfoWriteAPI
		PackageInfoReadAPI
*/

// NewPackageInfoWriteService  creates and configures a TwirpService that can be mounted
// on a router and dispatch calls for the PackageInfoWriteAPI rpc interface.
// This service is used for creating attestations.
func NewPackageInfoWriteService(tma *service.TMA, cfg []auth.ClientConfig, opts ...TwirpServiceOption) (*TwirpService, error) {
	twirpService, err := newTwirpService(tma, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp twirpService: %w", err)
	}

	server := rpc.NewPackageInfoWriteAPIServer(twirpService,
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

	twirpService.Handler = authMiddleware(server)

	return twirpService, nil
}

// NewPackageInfoReadService creates and configures a TwirpService that can be mounted
// on a router and dispatch calls for the PackageInfoReadAPI rpc interface.
// This service is used for reading attestations.
func NewPackageInfoReadService(tma *service.TMA, cfg []auth.ClientConfig, opts ...TwirpServiceOption) (*TwirpService, error) {
	twirpService, err := newTwirpService(tma, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp twirpService: %w", err)
	}

	server := rpc.NewPackageInfoReadAPIServer(twirpService,
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

	twirpService.Handler = authMiddleware(server)

	return twirpService, nil
}

/*
  NPM API Routes - PackageInfoWriteAPI
	  POST /twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation
*/

// CreatePackageAttestation creates an attestation for a given package as part of PackageInfoWriteAPI.
func (ts *TwirpService) CreatePackageAttestation(ctx context.Context, req *rpc.CreatePackageAttestationRequest) (*rpc.CreatePackageAttestationResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only npm clients are supported
	if !client.FromNpm() {
		return nil, ErrUnsupportedClient
	}

	// Get the bundle and purl from the request for the query
	bundle := req.GetBundle()
	purl := req.GetPurl()
	err = validatePurl(purl)
	if err != nil {
		return nil, err
	}

	// Create attestation
	createdAttestation, err := ts.tma.CreateNPMAttestation(ctx, bundle, attestation.IdentifiersNPM{
		DomainID: client.DomainID,
		Purl:     purl,
	})
	if err != nil {
		return nil, err
	}

	return &rpc.CreatePackageAttestationResponse{
		AttestationId: createdAttestation.ID,
	}, nil
}

/*
  NPM API Routes - PackageInfoReadAPI
	  POST /twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageAttestations
    POST /twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageProvenanceSummary
*/

// GetPackageAttestations returns all attestation records for a given package as part of PackageInfoReadAPI
func (ts *TwirpService) GetPackageAttestations(ctx context.Context, req *rpc.GetPackageAttestationsRequest) (*rpc.GetPackageAttestationsResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only npm clients are supported
	if !client.FromNpm() {
		return nil, ErrUnsupportedClient
	}

	// Get the purl from the request for the query
	purl := req.GetPurl()
	err = validatePurl(purl)
	if err != nil {
		return nil, err
	}

	identifiers := attestation.IdentifiersNPM{
		DomainID: client.DomainID,
		Purl:     purl,
	}

	// Get attestation records
	attestationRecords, err := ts.tma.GetNPMAttestations(ctx, identifiers)
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

	// map Records to bundles
	pkgAttestations := make([]*rpc.PackageAttestation, len(records))
	for i, ar := range records {
		pkgAttestations[i] = &rpc.PackageAttestation{
			Bundle:                   ar.Bundle,
			PredicateType:            ar.PredicateType,
			SignedAccessSignatureUrl: ar.SASUrl,
		}
	}

	return &rpc.GetPackageAttestationsResponse{Attestations: pkgAttestations}, nil
}

// GetPackageProvenanceSummary returns a summary of the provenance of a package as part of PackageInfoReadAPI.
func (ts *TwirpService) GetPackageProvenanceSummary(ctx context.Context, req *rpc.GetPackageProvenanceSummaryRequest) (*rpc.GetPackageProvenanceSummaryResponse, error) {
	// Get the current client
	client, err := auth.GetCurrentClient(ctx)
	if err != nil {
		return nil, err
	}

	// Only npm clients are supported
	if !client.FromNpm() {
		return nil, ErrUnsupportedClient
	}

	// Get the purl from the request for the query
	purl := req.GetPurl()
	err = validatePurl(purl)
	if err != nil {
		return nil, err
	}

	identifiers := attestation.IdentifiersNPM{
		DomainID: client.DomainID,
		Purl:     purl,
	}

	// Get provenance summary
	provenanceSummary, err := ts.tma.GetProvenanceAttestationSummary(ctx, identifiers)
	if err != nil {
		return nil, err
	}

	provenanceSummaryPB := &rpc.ProvenanceSummary{
		SubjectAlternativeName:            provenanceSummary.SubjectAlternativeName,
		CertificateIssuer:                 provenanceSummary.CertificateIssuer,
		Issuer:                            provenanceSummary.Issuer,
		IssuerDisplayName:                 provenanceSummary.IssuerDisplayName,
		BuildTrigger:                      provenanceSummary.BuildTrigger,
		BuildConfigUri:                    provenanceSummary.BuildConfigURI,
		SourceRepositoryUri:               provenanceSummary.SourceRepositoryURI,
		SourceRepositoryDigest:            provenanceSummary.SourceRepositoryDigest,
		SourceRepositoryRef:               provenanceSummary.SourceRepositoryRef,
		RunInvocationUri:                  provenanceSummary.RunInvocationURI,
		ExpiresAt:                         timestamppb.New(provenanceSummary.ExpiresAt),
		IncludedAt:                        timestamppb.New(provenanceSummary.IncludedAt),
		ResolvedSourceRepositoryCommitUri: provenanceSummary.ResolvedSourceRepositoryCommitURI,
		TransparencyLogUri:                provenanceSummary.TransparencyLogURI,
		BuildConfigDisplayName:            provenanceSummary.BuildConfigDisplayName,
		ResolvedBuildConfigUri:            provenanceSummary.ResolvedBuildConfigURI,
	}

	res := &rpc.GetPackageProvenanceSummaryResponse{
		ProvenanceSummary: provenanceSummaryPB,
	}

	return res, nil
}

// validatePurl validates the string is a Package URL (purl) format
func validatePurl(purl string) twirp.Error {
	// The FromString function will return an error if the input is not valid purl
	_, err := packageurl.FromString(purl)
	if err != nil {
		wrappedErr := fmt.Errorf("purl is not valid: %w", err)
		return twirp.NewError(twirp.InvalidArgument, wrappedErr.Error())
	}
	return nil
}
