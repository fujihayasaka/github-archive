package archive

import (
	"fmt"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/uuid"
)

type (
	// RepositoryLabel struct represents the labels within the repository
	RepositoryLabel struct {
		URL         string    `json:"url"`
		Name        string    `json:"name"`
		Color       string    `json:"color"`
		Description string    `json:"description"`
		CreatedAt   time.Time `json:"created_at"`
	}

	// SecurityAndAnalysis struct represents security and analysis settings
	SecurityAndAnalysis struct {
		DependencyGraph             bool `json:"dependency_graph"`
		VulnerabilityAlerts         bool `json:"vulnerability_alerts"`
		VulnerabilityUpdates        bool `json:"vulnerability_updates"`
		AdvancedSecurity            bool `json:"advanced_security"`
		TokenScanning               bool `json:"token_scanning"`
		TokenScanningPushProtection bool `json:"token_scanning_push_protection"`
	}

	// GeneralSettings struct represents general settings for the repository
	GeneralSettings struct {
		Template          *bool `json:"template,omitempty"`
		AllowForking      *bool `json:"allow_forking,omitempty"`
		Sponsorships      *bool `json:"sponsorships,omitempty"`
		Projects          *bool `json:"projects,omitempty"`
		Discussions       *bool `json:"discussions,omitempty"`
		MergeCommit       *bool `json:"merge_commit,omitempty"`
		SquashMerge       *bool `json:"squash_merge,omitempty"`
		RebaseMerge       *bool `json:"rebase_merge,omitempty"`
		AutoMerge         *bool `json:"auto_merge,omitempty"`
		DeleteBranchHeads *bool `json:"delete_branch_heads,omitempty"`
		UpdateBranch      *bool `json:"update_branch,omitempty"`
		GitLFSInArchives  *bool `json:"git_lfs_in_archives,omitempty"`
	}

	// ActionsGeneralSettings struct represents settings related to GitHub Actions
	ActionsGeneralSettings struct {
		ActionsDisabled               bool     `json:"actions_disabled"`
		AllowsAllActions              bool     `json:"allows_all_actions"`
		AllowsLocalActionsOnly        bool     `json:"allows_local_actions_only"`
		AllowsGitHubOwnedActions      bool     `json:"allows_github_owned_actions"`
		AllowsVerifiedActions         bool     `json:"allows_verified_actions"`
		AllowsSpecificActionsPatterns bool     `json:"allows_specific_actions_patterns"`
		Patterns                      []string `json:"patterns"`
	}

	// Page struct represents settings related to Pages.
	Page struct {
		CName         string `json:"cname"`
		HTTPSRedirect bool   `json:"https_redirect"`
		Source        string `json:"source,omitempty"`
		SourceRefName string `json:"source_ref_name"`
		SourceSubDir  string `json:"source_sub_dir"`
		IsPublic      bool   `json:"is_public"`
		SubDomain     string `json:"subdomain,omitempty"`
		ParentDomain  string `json:"parent_domain,omitempty"`
		Theme         string `json:"theme"`
		BuildType     string `json:"build_type"`
	}

	// Autolink represents settings related to an Autolink.
	Autolink struct {
		KeyPrefix      string `json:"key_prefix"`
		URLTemplate    string `json:"url_template"`
		IsAlphanumeric bool   `json:"is_alphanumeric"`
	}

	// RepositoryTopic represents settings related to a Repository Topic.
	RepositoryTopic struct {
		TopicURL   string    `json:"topic_url"`
		TopicName  string    `json:"topic_name"`
		State      string    `json:"state"`
		Repository string    `json:"repository"`
		Creator    string    `json:"creator"`
		CreatedAt  time.Time `json:"created_at"`
		UpdatedAt  time.Time `json:"updated_at"`
	}

	// Repository struct represents the main repository object
	Repository struct {
		Type                   string                  `json:"type"`
		URL                    string                  `json:"url"`
		Owner                  string                  `json:"owner"`
		Name                   string                  `json:"name"`
		Description            string                  `json:"description"`
		Website                string                  `json:"website"`
		Private                bool                    `json:"private"`
		HasIssues              bool                    `json:"has_issues"`
		HasWiki                bool                    `json:"has_wiki"`
		HasDownloads           bool                    `json:"has_downloads"`
		IsArchived             bool                    `json:"is_archived"`
		RepositoryLabels       []RepositoryLabel       `json:"labels"`
		Collaborators          []interface{}           `json:"collaborators"` // Empty array, so we use interface{}
		CreatedAt              time.Time               `json:"created_at"`
		GitURL                 string                  `json:"git_url"`
		DefaultBranch          string                  `json:"default_branch"`
		Webhooks               []*Webhook              `json:"webhooks"`
		PublicKeys             []interface{}           `json:"public_keys"` // Empty array, so we use interface{}
		RepositoryTopics       []*RepositoryTopic      `json:"repository_topics"`
		SecurityAndAnalysis    SecurityAndAnalysis     `json:"security_and_analysis"`
		Autolinks              []*Autolink             `json:"autolinks"`
		GeneralSettings        *GeneralSettings        `json:"general_settings"`
		ActionsGeneralSettings *ActionsGeneralSettings `json:"actions_general_settings"`
		Page                   *Page                   `json:"page"`
	}
)

// ToV1Repository converts an archive Repository to a v1.Repository
func (r *Repository) ToV1Repository() (*v1.Repository, error) {
	return &v1.Repository{
		ResourceId: r.URL,
		IsPrivate:  r.Private,
	}, nil
}

// ToV1InitialActionsSettings converts an archive Repository to a v1.InitialActionsSettings.
func (r *Repository) ToV1InitialActionsSettings() *v1.InitialActionsSettings {
	settings := &v1.InitialActionsSettings{
		ResourceId:               fmt.Sprintf("actionssettings-%s", r.URL),
		RepositoryResourceId:     r.URL,
		AllowsGithubOwnedActions: r.ActionsGeneralSettings.AllowsGitHubOwnedActions,
		AllowsVerifiedActions:    r.ActionsGeneralSettings.AllowsVerifiedActions,
		Patterns:                 r.ActionsGeneralSettings.Patterns,
	}

	// Exactly one of the following properties should be set to true within
	// an archive as they are mutually exclusive and should have a default.

	// Source for conversion: https://github.ghe.com/github/octoshift/blob/ea8f4353df1cb3ac72893d65794e25d8d9a37794/app/adapters/sources/github_archive/transformers/actions_settings.rb#L7
	switch {
	case r.ActionsGeneralSettings.AllowsAllActions:
		settings.ActionsPermissions = v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_ALL_ENABLED
	case r.ActionsGeneralSettings.AllowsLocalActionsOnly:
		settings.ActionsPermissions = v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
	case r.ActionsGeneralSettings.AllowsGitHubOwnedActions ||
		r.ActionsGeneralSettings.AllowsVerifiedActions ||
		r.ActionsGeneralSettings.AllowsSpecificActionsPatterns ||
		len(r.ActionsGeneralSettings.Patterns) > 0:
		settings.ActionsPermissions = v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
	default:
		settings.ActionsPermissions = v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INVALID
	}

	return settings
}

// ToV1InitialRepositorySettings converts an archive Repository to a v1.InitialRepositorySettings.
func (r *Repository) ToV1InitialRepositorySettings() *v1.InitialRepositorySettings {
	settings := &v1.InitialRepositorySettings{
		ResourceId:                     fmt.Sprintf("repositorysettings-%s", r.URL),
		RepositoryResourceId:           r.URL,
		Description:                    r.Description,
		DefaultBranch:                  r.DefaultBranch,
		HasWiki:                        r.HasWiki,
		HasIssues:                      r.HasIssues,
		HasDownloads:                   r.HasDownloads,
		HasDependencyGraph:             r.SecurityAndAnalysis.DependencyGraph,
		HasVulnerabilityAlerts:         r.SecurityAndAnalysis.VulnerabilityAlerts,
		HasVulnerabilityUpdates:        r.SecurityAndAnalysis.VulnerabilityUpdates,
		HasAdvancedSecurity:            r.SecurityAndAnalysis.AdvancedSecurity,
		HasTokenScanning:               r.SecurityAndAnalysis.TokenScanning,
		HasTokenScanningPushProtection: r.SecurityAndAnalysis.TokenScanningPushProtection,
	}
	if r.Webhooks != nil {
		webhooks := []*v1.Webhook{}
		for _, w := range r.Webhooks {
			webhooks = append(webhooks, &v1.Webhook{
				PayloadUrl:            w.PayloadURL,
				Active:                w.Active,
				EnableSslVerification: w.EnableSSLVerification,
				EventTypes:            w.EventTypes,
				ContentType:           w.ContentType,
			})
		}
		settings.Webhooks = webhooks
	}

	if r.GeneralSettings != nil {
		settings.GeneralRepositorySettings = &v1.GeneralRepositorySettings{
			IsTemplate:           setBoolIfNotNil(r.GeneralSettings.Template),
			HasAllowForking:      setBoolIfNotNil(r.GeneralSettings.AllowForking),
			HasSponsorships:      setBoolIfNotNil(r.GeneralSettings.Sponsorships),
			HasDiscussions:       setBoolIfNotNil(r.GeneralSettings.Discussions),
			HasMergeCommit:       setBoolIfNotNil(r.GeneralSettings.MergeCommit),
			HasSquashMerge:       setBoolIfNotNil(r.GeneralSettings.SquashMerge),
			HasRebaseMerge:       setBoolIfNotNil(r.GeneralSettings.RebaseMerge),
			HasAutoMerge:         setBoolIfNotNil(r.GeneralSettings.AutoMerge),
			HasDeleteBranchHeads: setBoolIfNotNil(r.GeneralSettings.DeleteBranchHeads),
			HasUpdateBranch:      setBoolIfNotNil(r.GeneralSettings.UpdateBranch),
			HasGitLfsInArchives:  setBoolIfNotNil(r.GeneralSettings.GitLFSInArchives),
			HasProjects:          setBoolIfNotNil(r.GeneralSettings.Projects),
		}
	}
	if r.Page != nil {
		settings.Page = &v1.Page{
			Source:        r.Page.Source,
			SourceRefName: r.Page.SourceRefName,
			SourceSubdir:  r.Page.SourceSubDir,
			IsPublic:      r.Page.IsPublic,
			BuildType:     r.Page.BuildType,
		}
	}
	if r.Autolinks != nil {
		autolinks := []*v1.Autolink{}
		for _, a := range r.Autolinks {
			autolinks = append(autolinks, &v1.Autolink{
				KeyPrefix:      a.KeyPrefix,
				UrlTemplate:    a.URLTemplate,
				IsAlphanumeric: a.IsAlphanumeric,
			})
		}
		settings.Autolinks = autolinks
	}
	if r.RepositoryTopics != nil {
		topics := []*v1.RepositoryTopic{}
		for _, t := range r.RepositoryTopics {
			topics = append(topics, &v1.RepositoryTopic{
				TopicName:         t.TopicName,
				TopicUrl:          t.TopicURL,
				State:             t.State,
				CreatorResourceId: t.Creator,
				CreatedAt:         toTimestamp(t.CreatedAt),
				UpdatedAt:         toTimestamp(t.UpdatedAt),
			})
		}
		settings.RepositoryTopics = topics
	}
	return settings
}

// ToV1RepositoryLabels converts an archive Repositories labels to a list of v1.RepositoryLabel.
func (r *Repository) ToV1RepositoryLabels() []*v1.RepositoryLabel {
	var repoLabels []*v1.RepositoryLabel
	for _, l := range r.RepositoryLabels {
		repoLabels = append(repoLabels, &v1.RepositoryLabel{
			ResourceId:  l.URL,
			Name:        l.Name,
			Color:       l.Color,
			Description: l.Description,
			CreatedAt:   toTimestamp(r.CreatedAt),
		})
	}

	return repoLabels
}

// prepareRepositoryLabelsBatches takes a list of repository labels for a repository
// and returns multiple batches enforcing a max batch size
// for the underlying repository labels resource. A batchSize greater than zero is required.
func prepareRepositoryLabelsBatches(repositoryID string, ls []*v1.RepositoryLabel, batchSize int) ([]*v1.RepositoryLabelsBatch, error) {
	if batchSize <= 0 {
		return nil, fmt.Errorf("positive batch size is required")
	}

	batches := []*v1.RepositoryLabelsBatch{}
	currentBatch := &v1.RepositoryLabelsBatch{}
	addBatch := func() {
		if len(currentBatch.Labels) == 0 {
			return
		}
		currentBatch.RepositoryId = repositoryID
		currentBatch.ResourceId = fmt.Sprintf("repository-labels-%s-%s", repositoryID, uuid.New().String())
		batches = append(batches, currentBatch)
		currentBatch = &v1.RepositoryLabelsBatch{}
	}

	for _, l := range ls {
		currentBatch.Labels = append(currentBatch.Labels, l)
		if len(currentBatch.Labels) >= batchSize {
			addBatch()
		}
	}

	// add any remaining items to a new batch.
	addBatch()

	return batches, nil
}
