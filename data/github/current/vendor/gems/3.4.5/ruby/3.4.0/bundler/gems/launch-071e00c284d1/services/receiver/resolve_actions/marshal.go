package resolveactions

import (
	"context"
	"fmt"
	"time"

	"github.com/pkg/errors"

	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pb/deploy"
	terrs "github.com/github/launch/types/errors"
)

type ServiceRequest struct {
	Actions        []Action `json:"actions"`
	IsHostedRunner bool     `json:"is_hosted_runner"`
}

type Action struct {
	Name    string `json:"action"`
	Version string `json:"version"`
	Path    string `json:"path,omitempty"`
}

type ServiceResponse struct {
	Actions map[string]ResolvedAction  `json:"actions"`
	Errors  map[string]ResolutionError `json:"errors"`
}

type ResolutionError struct {
	Message string `json:"message"`
}

type ResolvedAction struct {
	Name           string          `json:"name"`
	ResolvedName   string          `json:"resolved_name"`
	Version        string          `json:"version"`
	ResolvedSha    string          `json:"resolved_sha"`
	TarURL         string          `json:"tar_url"`
	ZipURL         string          `json:"zip_url"`
	Authentication *Authentication `json:"authentication"`
	PackageDetails *PackageDetails `json:"package_details"`
}

type Authentication struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
}

type PackageDetails struct {
	Version        string `json:"version"`
	ManifestDigest string `json:"manifest_digest"`
}

func (s *Servicer) ResolveActions(ctx context.Context, wfid string, jid string, svcRequest ServiceRequest) (*ServiceResponse, error) {
	return ResolveActions(ctx, s.Deployer, wfid, jid, svcRequest)
}

func ResolveActions(ctx context.Context, deployer deploy.LaunchDeploymentService, wfid string, jid string, svcRequest ServiceRequest) (*ServiceResponse, error) {
	deployerRequest := &deploy.ResolveActionsRequest{
		WorkflowId:     wfid,
		JobId:          jid,
		Actions:        make([]*deploy.ActionReference, len(svcRequest.Actions)),
		IsHostedRunner: svcRequest.IsHostedRunner,
	}
	for i, a := range svcRequest.Actions {
		deployerRequest.Actions[i] = &deploy.ActionReference{
			Name:    a.Name,
			Version: a.Version,
			Path:    a.Path,
		}
	}

	deployerResponse, err := deployer.ResolveActions(ctx, deployerRequest)
	if err != nil {
		if terrs.IsRateLimitError(err) {
			return nil, err
		}
	}

	if _, message, ok := svcerr.ExtractHTTPError(err); ok {
		svcResponse := ServiceResponse{
			Actions: make(map[string]ResolvedAction),
			Errors:  make(map[string]ResolutionError, 1),
		}
		svcResponse.Errors["policy"] = ResolutionError{
			Message: message,
		}
		return &svcResponse, nil
	}
	if err != nil {
		err := errors.Wrap(err, "Resolve actions RPC call to deployer failed")
		return nil, err
	}

	svcResponse := ServiceResponse{
		Actions: make(map[string]ResolvedAction, len(deployerResponse.Actions)),
		Errors:  make(map[string]ResolutionError, len(deployerResponse.Errors)),
	}

	for _, action := range deployerResponse.Actions {
		var actionAuth *Authentication
		var packageDetails *PackageDetails

		if action.Authentication != nil {
			tokenExpiresAt := action.Authentication.ExpiresAt.AsTime()
			actionAuth = &Authentication{
				Token:     action.Authentication.Token,
				ExpiresAt: tokenExpiresAt.Format(time.RFC3339Nano),
			}
		}

		if action.PackageDetails != nil {
			packageDetails = &PackageDetails{
				Version:        action.PackageDetails.Version,
				ManifestDigest: action.PackageDetails.ManifestDigest,
			}
		}

		nameWithVersion := fmt.Sprintf("%s@%s", action.Action.Name, action.Action.Version)

		svcResponse.Actions[nameWithVersion] = ResolvedAction{
			Name:           action.Action.Name,
			ResolvedName:   action.ResolvedName,
			Version:        action.Action.Version,
			ResolvedSha:    action.ResolvedSha,
			TarURL:         action.TarUrl,
			ZipURL:         action.ZipUrl,
			Authentication: actionAuth,
			PackageDetails: packageDetails,
		}
	}

	for _, resolutionError := range deployerResponse.Errors {
		svcResponse.Errors[resolutionError.GetAction().NameWithVersion()] = ResolutionError{
			Message: resolutionError.GetMessage(),
		}
	}

	return &svcResponse, nil
}
