package resource

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	initialRepositorySettings struct {
		baseHandler
		pb *v1.InitialRepositorySettings
	}

	// InitialRepositorySettingsError is an error type for a failed repository settings
	// import. Most resources return a Twirp error, but this resource may also fail without
	// a Twirp error at import time. This error type is used to handle that case so that
	// it can be detected by the caller without having to parse the error message.
	InitialRepositorySettingsError struct {
		Err error
	}
)

var _ handler = (*initialRepositorySettings)(nil)

func newInitialRepositorySettings(pb *v1.InitialRepositorySettings, logger log.Logger) *initialRepositorySettings {
	return &initialRepositorySettings{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (r *initialRepositorySettings) resourceID() string {
	return r.pb.ResourceId
}

func (r *initialRepositorySettings) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(r.pb.RepositoryResourceId)
	for _, t := range r.pb.RepositoryTopics {
		deps.strDeps.Add(t.CreatorResourceId)
		if t.TopicUrl != "" {
			parsedURL, err := url.Parse(t.TopicUrl)
			if err != nil {
				r.logger.WithError(err).Error("failed to parse repository settings topic url")
				return nil, fmt.Errorf("failed to parse repository settings topic url: %w", err)
			}
			baseURL := fmt.Sprintf("%s://%s", parsedURL.Scheme, parsedURL.Host)
			deps.strDeps.Add(baseURL)
		}
	}
	return deps, nil
}

func (r *initialRepositorySettings) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	repoID := resolved[r.pb.RepositoryResourceId].int64Val
	req := &octov1.UpdateRepositoryRequest{
		RepositoryId:                   repoID,
		DefaultBranch:                  r.pb.DefaultBranch,
		Description:                    r.pb.Description,
		HasWiki:                        r.pb.HasWiki,
		HasIssues:                      r.pb.HasIssues,
		HasDownloads:                   r.pb.HasDownloads,
		HasDependencyGraph:             r.pb.HasDependencyGraph,
		HasVulnerabilityAlerts:         r.pb.HasVulnerabilityAlerts,
		HasVulnerabilityUpdates:        r.pb.HasVulnerabilityUpdates,
		HasAdvancedSecurity:            r.pb.HasAdvancedSecurity,
		HasTokenScanning:               r.pb.HasTokenScanning,
		HasTokenScanningPushProtection: r.pb.HasTokenScanningPushProtection,
	}
	if r.pb.Page != nil {
		req.Page = &octov1.Page{
			Source:        r.pb.Page.Source,
			SourceRefName: r.pb.Page.SourceRefName,
			SourceSubdir:  r.pb.Page.SourceSubdir,
			IsPublic:      r.pb.Page.IsPublic,
			BuildType:     r.pb.Page.BuildType,
		}
	}
	if r.pb.GeneralRepositorySettings != nil {
		req.GeneralRepositorySettings = &octov1.GeneralRepositorySettings{
			IsTemplate:           r.pb.GeneralRepositorySettings.IsTemplate,
			HasAllowForking:      r.pb.GeneralRepositorySettings.HasAllowForking,
			HasSponsorships:      r.pb.GeneralRepositorySettings.HasSponsorships,
			HasDiscussions:       r.pb.GeneralRepositorySettings.HasDiscussions,
			HasMergeCommit:       r.pb.GeneralRepositorySettings.HasMergeCommit,
			HasSquashMerge:       r.pb.GeneralRepositorySettings.HasSquashMerge,
			HasRebaseMerge:       r.pb.GeneralRepositorySettings.HasRebaseMerge,
			HasAutoMerge:         r.pb.GeneralRepositorySettings.HasAutoMerge,
			HasDeleteBranchHeads: r.pb.GeneralRepositorySettings.HasDeleteBranchHeads,
			HasUpdateBranch:      r.pb.GeneralRepositorySettings.HasUpdateBranch,
			HasGitLfsInArchives:  r.pb.GeneralRepositorySettings.HasGitLfsInArchives,
			HasProjects:          r.pb.GeneralRepositorySettings.HasProjects,
		}
	}
	for _, w := range r.pb.Webhooks {
		req.Webhooks = append(req.Webhooks, &octov1.Webhook{
			PayloadUrl:            w.PayloadUrl,
			Active:                w.Active,
			EnableSslVerification: w.EnableSslVerification,
			EventTypes:            w.EventTypes,
			ContentType:           w.ContentType,
		})
	}

	for _, t := range r.pb.RepositoryTopics {
		creator := resolved[t.CreatorResourceId].strVal
		topicURL := ""
		if t.TopicUrl != "" {
			parsedURL, err := url.Parse(t.TopicUrl)
			if err != nil {
				r.logger.WithError(err).Error("failed to parse repository settings topic url")
				return fmt.Errorf("failed to parse repository settings topic url: %w", err)
			}
			baseURL := fmt.Sprintf("%s://%s", parsedURL.Scheme, parsedURL.Host)
			topicURL = resolved[baseURL].strVal
		}
		req.RepositoryTopics = append(req.RepositoryTopics, &octov1.RepositoryTopic{
			TopicName:    t.TopicName,
			TopicUrl:     topicURL,
			State:        convertRepositoryTopicState(t.State),
			CreatorLogin: creator,
			CreatedAt:    t.CreatedAt,
			UpdatedAt:    t.UpdatedAt,
		})
	}

	for _, a := range r.pb.Autolinks {
		req.Autolinks = append(req.Autolinks, &octov1.Autolink{
			KeyPrefix:      a.KeyPrefix,
			UrlTemplate:    a.UrlTemplate,
			IsAlphanumeric: a.IsAlphanumeric,
		})
	}

	res, err := importer.UpdateRepository(ctx, req)
	if err != nil {
		r.logger.WithError(err).Error("failed to update repository settings")
		return fmt.Errorf("failed to update repository settings: %w", err)
	}

	var errs error
	if res.Repository.PageErrorMessage != "" {
		errs = errors.Join(errs, fmt.Errorf("failed to update page settings: %s", res.Repository.PageErrorMessage))
	}
	if len(res.Repository.GeneralSettingErrors) > 0 {
		errs = errors.Join(errs, fmt.Errorf("failed to update general repository settings: %v", res.Repository.GeneralSettingErrors))
	}
	if len(res.Repository.SecuritySettingErrors) > 0 {
		errs = errors.Join(errs, fmt.Errorf("failed to update security repository settings: %v", res.Repository.SecuritySettingErrors))
	}
	if errs != nil {
		r.logger.WithError(errs).Error("failed to update repository settings")
		return &InitialRepositorySettingsError{Err: errs}
	}

	return nil
}

func convertRepositoryTopicState(state string) octov1.RepositoryTopicState {
	// Note, I'm guessing on most of these string values as I can't find any
	// examples of them being used in archives. An INVALID state may indicate
	// a case is not captured correctly.
	switch strings.ToLower(state) {
	case "created":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_CREATED
	case "suggested":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_SUGGESTED
	case "declined_not_relevant":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_DECLINED_NOT_RELEVANT
	case "declined_too_specific":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_DECLINED_TOO_SPECIFIC
	case "declined_personal_preference":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_DECLINED_PERSONAL_PREFERENCE
	case "declined_too_general":
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_DECLINED_TOO_GENERAL
	default:
		return octov1.RepositoryTopicState_REPOSITORY_TOPIC_STATE_INVALID
	}
}

// Error returns a string representation of the error
func (e *InitialRepositorySettingsError) Error() string {
	return e.Err.Error()
}
