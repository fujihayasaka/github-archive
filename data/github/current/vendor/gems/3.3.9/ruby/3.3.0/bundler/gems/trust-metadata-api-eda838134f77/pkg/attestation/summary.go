package attestation

import (
	"context"
	"crypto/x509"
	"encoding/asn1"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/trust-metadata-api/pkg/o11y"
	in_toto "github.com/in-toto/attestation/go/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/sigstore/sigstore-go/pkg/verify"
)

const (
	GitHubActionsIssuer = "https://token.actions.githubusercontent.com"
	GitLabCIIssuer      = "https://gitlab.com"

	// Legacy SLSA Provenance Predicate Type
	PredicateSLSAProvenanceV02 = "https://slsa.dev/provenance/v0.2"
)

// ErrCertificateSummary represents an error encountered when parsing a certificate
type ErrCertificateSummary struct {
	wrapped error
	extID   asn1.ObjectIdentifier
}

func (e ErrCertificateSummary) Error() string {
	msg := "failed to parse certificate"
	if e.wrapped == nil {
		return msg
	}

	return fmt.Sprintf("%s: %s (%s)", msg, e.wrapped.Error(), e.extID.String())
}

func (e ErrCertificateSummary) Unwrap() error {
	return e.wrapped
}

// FulcioCertificateSummary represents a summary of an X509 certificate
type FulcioCertificateSummary struct {
	IsPostFulcioV1_2          bool      `json:"-"`
	SubjectAlternativeNameURL string    `json:"subjectAlternativeNameURL"` //nolint:tagliatelle
	CertificateIssuer         string    `json:"certificateIssuer"`
	Issuer                    string    `json:"issuer"`
	BuildTrigger              string    `json:"buildTrigger"`
	BuildConfigURI            string    `json:"buildConfigURI"`      //nolint:tagliatelle
	SourceRepositoryURI       string    `json:"sourceRepositoryURI"` //nolint:tagliatelle
	SourceRepositoryDigest    string    `json:"sourceRepositoryDigest"`
	SourceRepositoryRef       string    `json:"sourceRepositoryRef"`
	RunInvocationURI          string    `json:"runInvocationURI"` //nolint:tagliatelle
	NotAfter                  time.Time `json:"notAfter"`
}

// NewFulcioCertificateSummary creates a new Summary from an Fulcio x509 certificate
func NewFulcioCertificateSummary(c *x509.Certificate) (FulcioCertificateSummary, error) {
	// Our internal Fulcio cert summary
	fcs := FulcioCertificateSummary{
		NotAfter: c.NotAfter,
	}

	// Use OID 1.3.6.1.4.1.57264.1.8 to see if it's a Fulcio v1.2+ certificate
	// TODO: Switch to a different OID to identify Fulcio cert versions if they introduce one to track versions
	for _, ext := range c.Extensions {
		if ext.Id.Equal(certificate.OIDIssuerV2) {
			fcs.IsPostFulcioV1_2 = true
		}
	}

	if fcs.IsPostFulcioV1_2 {
		// Fulcio v1.2 certificate or newer
		// use sigstore-go to get a summary of the Fulcio certificate
		sc, err := certificate.SummarizeCertificate(c)
		if err != nil {
			return FulcioCertificateSummary{}, err
		}

		fcs.BuildConfigURI = sc.BuildConfigURI
		fcs.BuildTrigger = sc.BuildTrigger
		fcs.CertificateIssuer = sc.CertificateIssuer
		fcs.Issuer = sc.Issuer
		fcs.RunInvocationURI = sc.RunInvocationURI
		fcs.SourceRepositoryDigest = sc.SourceRepositoryDigest
		fcs.SourceRepositoryRef = sc.SourceRepositoryRef
		fcs.SourceRepositoryURI = sc.SourceRepositoryURI
		fcs.SubjectAlternativeNameURL = sc.SubjectAlternativeName
	} else {
		// Fulcio v1.1 certificates or older
		fcs.CertificateIssuer = c.Issuer.String()

		if len(c.URIs) > 0 {
			fcs.SubjectAlternativeNameURL = c.URIs[0].String()
		}

		// Loop over the extensions and grab the data
		// ignore SA1019 because we need to support deprecated OID constants for older certificates
		for _, ext := range c.Extensions {
			//nolint:staticcheck
			switch {
			case ext.Id.Equal(certificate.OIDIssuer):
				fcs.Issuer = string(ext.Value)
			case ext.Id.Equal(certificate.OIDGitHubWorkflowTrigger):
				fcs.BuildTrigger = string(ext.Value)
			case ext.Id.Equal(certificate.OIDGitHubWorkflowSHA):
				fcs.SourceRepositoryDigest = string(ext.Value)
			case ext.Id.Equal(certificate.OIDGitHubWorkflowName):
				// WorkflowName cannot be made into an URI, so we NOP
				// cs.BuildConfigURI = ""
			case ext.Id.Equal(certificate.OIDGitHubWorkflowRepository):
				// not actually a URI, but since it's specifically a _GitHub_ nwo
				// we can convert it into a URI:
				fcs.SourceRepositoryURI = "https://github.com/" + string(ext.Value)
			case ext.Id.Equal(certificate.OIDGitHubWorkflowRef):
				fcs.SourceRepositoryRef = string(ext.Value)
			}
			//nolint:revive
		}
	}

	return fcs, nil
}

type ProvenanceSummary struct { //nolint:revive
	// Fulcio certificate summary's fields, with a minor tweak to the SAN
	SubjectAlternativeName string    `json:"subjectAlternativeName"`
	CertificateIssuer      string    `json:"certificateIssuer"`
	Issuer                 string    `json:"issuer"`
	IssuerDisplayName      string    `json:"issuerDisplayName"`
	BuildTrigger           string    `json:"buildTrigger"`
	BuildConfigURI         string    `json:"buildConfigURI"`      //nolint:tagliatelle
	SourceRepositoryURI    string    `json:"sourceRepositoryURI"` //nolint:tagliatelle
	SourceRepositoryDigest string    `json:"sourceRepositoryDigest"`
	SourceRepositoryRef    string    `json:"sourceRepositoryRef"`
	RunInvocationURI       string    `json:"runInvocationURI"` //nolint:tagliatelle
	ExpiresAt              time.Time `json:"expiresAt"`

	// fetched from transparency log
	IncludedAt time.Time `json:"includedAt"`

	// Derived from the cert's metadata
	ResolvedSourceRepositoryCommitURI string `json:"resolvedSourceRepositoryCommitURI"` //nolint:tagliatelle
	TransparencyLogURI                string `json:"transparencyLogURI"`                //nolint:tagliatelle
	BuildConfigDisplayName            string `json:"buildConfigDisplayName"`
	ResolvedBuildConfigURI            string `json:"resolvedBuildConfigURI"` //nolint:tagliatelle
	ArtifactName                      string `json:"artifactName"`
}

// NewProvenanceSummary takes a Bundle and generates a summary of its metadata
// using the Fulcio certificate, the transparency log, and, for older certificates,
// the contents of the SLSA provenance predicate.
func NewProvenanceSummary(ctx context.Context, bundle *sgbundle.Bundle) (ProvenanceSummary, error) {
	_, span := o11y.NamedSpan(ctx, "NewProvenanceSummary")
	defer span.End()

	leafCert, err := leafCertificate(bundle)
	if err != nil {
		return ProvenanceSummary{}, fmt.Errorf("getting leaf certificate: %w", err)
	}
	fcs, err := NewFulcioCertificateSummary(leafCert)
	if err != nil {
		return ProvenanceSummary{}, fmt.Errorf("provenance summary: %w", err)
	}

	ps := ProvenanceSummary{
		SubjectAlternativeName: fcs.SubjectAlternativeNameURL,
		CertificateIssuer:      fcs.CertificateIssuer,
		Issuer:                 fcs.Issuer,
		BuildTrigger:           fcs.BuildTrigger,
		BuildConfigURI:         fcs.BuildConfigURI,
		SourceRepositoryURI:    fcs.SourceRepositoryURI,
		SourceRepositoryDigest: fcs.SourceRepositoryDigest,
		SourceRepositoryRef:    fcs.SourceRepositoryRef,
		RunInvocationURI:       fcs.RunInvocationURI,
		ExpiresAt:              fcs.NotAfter,
	}

	// Get the envelope & statement from the bundle to fill out some details in the summary
	envelope, err := bundle.Envelope()
	if err != nil {
		return ProvenanceSummary{}, fmt.Errorf("getting envelope: %w", err)
	}
	statement, err := envelope.Statement()
	if err != nil {
		return ProvenanceSummary{}, fmt.Errorf("getting statement: %w", err)
	}

	// For older certificates before Fulcio v1.2
	if !fcs.IsPostFulcioV1_2 {
		ps = fillInProvenanceSummaryForOldBundles(ps, statement)
	}

	// The artifact name is the subject name of the statement
	if len(statement.Subject) > 0 {
		// for now we assume that the subject name is the first item in the collection
		ps.ArtifactName = statement.Subject[0].Name
	}

	// For every type of supported issuer, we want to provide a human-readable
	// label and build config details
	switch ps.Issuer { //nolint:gocritic
	case GitHubActionsIssuer:
		ps = fillInGitHubProvenanceDetails(ps)
	case GitLabCIIssuer:
		ps = fillInGitLabProvenanceDetails(ps)
	}

	entries, err := bundle.TlogEntries()
	if err != nil {
		return ProvenanceSummary{}, fmt.Errorf("fetching tlog entries: %w", err)
	}

	if len(entries) > 0 {
		ps.TransparencyLogURI = fmt.Sprintf("https://search.sigstore.dev/?logIndex=%d", entries[0].LogIndex())
		ps.IncludedAt = entries[0].IntegratedTime().UTC()
	}

	return ps, nil
}

func fillInProvenanceSummaryForOldBundles(ps ProvenanceSummary, statement *in_toto.Statement) ProvenanceSummary {
	// In the TMA, Fulcio v1.1 certificates or older always shipped with
	// SLSA Provenance v0.2
	if statement.PredicateType != PredicateSLSAProvenanceV02 {
		return ps
	}

	if predicate := statement.GetPredicate(); predicate != nil {
		predicateMap := predicate.AsMap()
		if invocation, ok := predicateMap["invocation"].(map[string]interface{}); ok {
			if environment, ok := invocation["environment"].(map[string]interface{}); ok {
				if ghWorkflowRef, ok := environment["GITHUB_WORKFLOW_REF"].(string); ok && len(ghWorkflowRef) > 0 {
					ps.BuildConfigURI = "https://github.com/" + ghWorkflowRef
				} else {
					ps.BuildConfigURI = ps.SubjectAlternativeName
				}
			}
		}
		if metadata, ok := predicateMap["metadata"].(map[string]interface{}); ok {
			if buildInvocationID, ok := metadata["buildInvocationId"].(string); ok {
				// invocation ids consist of RUN_ID-ATTEMPT_ID, so we will split on the dash
				splitBuildInvocationID := strings.Split(buildInvocationID, "-")
				if len(splitBuildInvocationID) == 2 {
					runID := splitBuildInvocationID[0]
					attemptID := splitBuildInvocationID[1]

					ps.RunInvocationURI = fmt.Sprintf("%s/actions/runs/%s/attempts/%s", ps.SourceRepositoryURI, runID, attemptID)
				}
			}
		}
	}

	return ps
}

func fillInGitHubProvenanceDetails(ps ProvenanceSummary) ProvenanceSummary {
	ps.IssuerDisplayName = "GitHub Actions"

	// ResolvedSourceRepositoryCommitURI links directly to a web view of the
	// source code at the time of the build. This link is not provided in
	// the provenance metadata, so we construct it using info we can derive
	// from the cert.
	if strings.HasPrefix(ps.SourceRepositoryURI, "https://github.com") {
		ps.ResolvedSourceRepositoryCommitURI = fmt.Sprintf("%s/tree/%s", ps.SourceRepositoryURI, ps.SourceRepositoryDigest)
	}
	// Ignore the @refs/* suffix on BuildConfigURI as we only want to display the relative config file path
	splitBuildConfigURI := strings.Split(ps.BuildConfigURI, "@")
	// Relative pathname to the workflow file
	ps.BuildConfigDisplayName = strings.Replace(splitBuildConfigURI[0], ps.SourceRepositoryURI+"/", "", 1)
	// GHA provides a way to link to the workflow file in the actions UI, tying it back to the run
	splitRunInvocationURI := strings.Split(ps.RunInvocationURI, "/attempts/")
	parts := []string{
		splitRunInvocationURI[0],
		"workflow",
	}
	ps.ResolvedBuildConfigURI = strings.Join(parts, "/")

	return ps
}

func fillInGitLabProvenanceDetails(ps ProvenanceSummary) ProvenanceSummary {
	ps.IssuerDisplayName = "GitLab CI/CD"

	// ResolvedSourceRepositoryCommitURI links directly to a web view of the
	// source code at the time of the build. This link is not provided in
	// the provenance metadata, so we construct it using info we can derive
	// from the cert.
	if strings.HasPrefix(ps.SourceRepositoryURI, "https://gitlab.com") {
		ps.ResolvedSourceRepositoryCommitURI = fmt.Sprintf("%s/-/tree/%s", ps.SourceRepositoryURI, ps.SourceRepositoryDigest)
	}

	// The initial GitLab Fulcio certs set the job URL as the BuildConfigURI
	// which isn't very useful so we hardcode the config file, updated certs
	// include a source URI with the .gitlab-ci.yml file and ref, e.g.
	// https://gitlab.com/feelepxyz/gitlab-npm-provenance//.gitlab-ci.yml@refs/heads/main
	if strings.HasPrefix(ps.BuildConfigURI, ps.SourceRepositoryURI+"/-/jobs/") {
		ps.BuildConfigDisplayName = ".gitlab-ci.yml"
	} else {
		// Ignore the @refs/* suffix on BuildConfigURI as we only want to display the relative config file path
		buildConfigWithoutRef := strings.Split(ps.BuildConfigURI, "@")[0]
		buildConfigParts := strings.Split(buildConfigWithoutRef, "//")
		// Relative pathname to the ci config file (separated by double forward slash //)
		ps.BuildConfigDisplayName = buildConfigParts[len(buildConfigParts)-1]
	}
	// Construct the link to the CI file
	ps.ResolvedBuildConfigURI = fmt.Sprintf("%s/-/blob/%s/%s", ps.SourceRepositoryURI, ps.SourceRepositoryDigest, ps.BuildConfigDisplayName)

	return ps
}

// GetWorkflowRunIDFromBundle returns the ID of the workflow
func GetWorkflowRunIDFromBundle(bundle *sgbundle.Bundle) (uint64, error) {
	leafCert, err := leafCertificate(bundle)
	if err != nil {
		return 0, fmt.Errorf("getting leaf certificate: %w", err)
	}
	fcs, err := NewFulcioCertificateSummary(leafCert)
	if err != nil {
		return 0, fmt.Errorf("parsing fulcio certificate: %w", err)
	}

	// For older certificates before Fulcio v1.2
	if !fcs.IsPostFulcioV1_2 {
		envelope, err := bundle.Envelope()
		if err != nil {
			return 0, fmt.Errorf("getting envelope: %w", err)
		}

		statement, err := envelope.Statement()
		if err != nil {
			return 0, fmt.Errorf("getting statement: %w", err)
		}

		if predicate := statement.GetPredicate(); predicate != nil {
			predicateMap := predicate.AsMap()
			if metadata, ok := predicateMap["metadata"].(map[string]interface{}); ok {
				if buildInvocationID, ok := metadata["buildInvocationId"].(string); ok {
					// invocation ids consist of RUN_ID-ATTEMPT_ID, so we will split on the dash
					splitBuildInvocationID := strings.Split(buildInvocationID, "-")
					if len(splitBuildInvocationID) == 2 {
						runIDStr := splitBuildInvocationID[0]
						return strconv.ParseUint(runIDStr, 10, 64)
					}
				}
			}
		}
	} else if fcs.RunInvocationURI != "" {
		// extract this https://github.com/github-early-access/generate-build-provenance/actions/runs/7751033546/attempts/1 to 7751033546
		splitRunInvocationURI := strings.Split(fcs.RunInvocationURI, "/")
		if len(splitRunInvocationURI) == 10 {
			runIDStr := splitRunInvocationURI[7]
			return strconv.ParseUint(runIDStr, 10, 64)
		}
	}

	return 0, fmt.Errorf("could not find workflow run ID")
}

func leafCertificate(entity verify.SignedEntity) (*x509.Certificate, error) {
	verificationContent, err := entity.VerificationContent()
	if err != nil {
		return nil, fmt.Errorf("getting verification content: %w", err)
	}
	cert := verificationContent.GetCertificate()
	if cert == nil {
		return nil, fmt.Errorf("certificate chain is empty")
	}
	return cert, nil
}

// ParseDERString decodes a DER-encoded string and stores the value in parsedVal.
// Returns an error if the unmarshalling fails or if there are trailing bytes in the encoding.
func ParseDERString(val []byte, parsedVal *string) error {
	rest, err := asn1.Unmarshal(val, parsedVal)
	if err != nil {
		return fmt.Errorf("unexpected error unmarshalling DER-encoded string: %w", err)
	}
	if len(rest) != 0 {
		return errors.New("unexpected trailing bytes in DER-encoded string")
	}
	return nil
}
