package twirp

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/remediation"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
)

// validateWildcardForPackageException ensures that the pattern provided meets our
// wildcard rules:
// - Only one '*' character is allowed
// - There must be at least two other characters besides the '*'
// - The pattern must match the package name
func validateWildcardForPackageException(pattern, packageName string) error {
	// The basics: only one * is allowed and there must be at least two other characters
	numberOfWildcards := strings.Count(pattern, "*")
	if numberOfWildcards > 1 {
		return fmt.Errorf("invalid pattern %q: only one wildcard '*' is allowed", pattern)
	}
	if len(pattern) < 3 {
		return fmt.Errorf("invalid pattern %q: must have at least two non-wildcard characters", pattern)
	}

	if numberOfWildcards == 0 {
		// No wildcard, must match exactly
		if pattern != packageName {
			return fmt.Errorf("invalid pattern %q: does not match package name %q", pattern, packageName)
		}
		return nil
	}

	if !models.WildcardNameMatch(pattern, packageName) {
		return fmt.Errorf("invalid pattern %q: does not match package name %q", pattern, packageName)
	}

	return nil
}

// CreatePackageException creates a new package exception.
func (s *Server) CreatePackageException(ctx context.Context, req *proto.CreatePackageExceptionRequest) (*proto.CreatePackageExceptionResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}
	if req.AlertNumber == 0 {
		return nil, twirp.RequiredArgumentError("alert_number")
	}
	if req.PolicyLevel == proto.PolicyLevel_POLICY_LEVEL_UNKNOWN {
		return nil, twirp.RequiredArgumentError("policy_level")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.AlertNumber)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	packageNameForException := alert.PackageName
	if req.Pattern != "" {
		err := validateWildcardForPackageException(req.Pattern, alert.PackageName)
		if err != nil {
			return nil, twirp.InvalidArgumentError("pattern", err.Error())
		}
		packageNameForException = req.Pattern
	}

	incomingLicense := alert.SPDXLicenseExpression
	if incomingLicense == "" {
		incomingLicense = evaluator.LicenseRefEmpty
	}

	extraAllowedSpdxIDs, err := spdxexp.ExtractLicenses(incomingLicense)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("failed to parse alert license %q: %w", incomingLicense, err))
	}

	action := proto.PackageAction_PACKAGE_ACTION_ALLOWED
	if req.Action != proto.PackageAction_PACKAGE_ACTION_UNKNOWN {
		action = req.Action
	}

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                packageNameForException,
		Action:              action,
		Reason:              "Exception created via API",
		ExtraAllowedSpdxIds: extraAllowedSpdxIDs,
		Contexts:            req.Contexts,
	}

	err = remediation.AddPackagePolicyForAlert(ctx, s.app, alert, packagePolicy, req.Contexts, req.PolicyLevel, req.Comment, req.UserId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.CreatePackageExceptionResponse{
		Success: true,
	}, nil
}

// AddLicensesForAlert adds licenses to a policy to remediate an alert.
func (s *Server) AddLicensesForAlert(ctx context.Context, req *proto.AddLicensesForAlertRequest) (*proto.AddLicensesForAlertResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.AlertNumber == 0 {
		return nil, twirp.RequiredArgumentError("alert_number")
	}
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}
	if req.PolicyLevel == proto.PolicyLevel_POLICY_LEVEL_UNKNOWN {
		return nil, twirp.RequiredArgumentError("policy_level")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.AlertNumber)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	licenses, err := spdxexp.ExtractLicenses(alert.SPDXLicenseExpression)
	if err != nil {
		return nil, twirp.InternalErrorWith(fmt.Errorf("failed to parse alert license %q: %w", alert.SPDXLicenseExpression, err))
	}
	if valid, invalidLicenses := spdxexp.ValidateLicenses(licenses); !valid {
		return nil, twirp.InvalidArgumentError("spdx_ids", fmt.Sprintf("invalid SPDX license identifiers: %v", invalidLicenses))
	}

	// Normalize all SPDX IDs to canonical case
	normalizedLicenses := make([]string, len(licenses))
	for i, license := range licenses {
		normalizedLicenses[i] = evaluator.NormalizeSpdxID(license)
	}

	err = remediation.AddLicensesToPolicyForAlert(ctx, s.app, alert, normalizedLicenses, req)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.AddLicensesForAlertResponse{
		Success:       true,
		AddedLicenses: normalizedLicenses,
		PolicyLevel:   req.PolicyLevel,
	}, nil
}
