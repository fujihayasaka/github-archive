# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryModelsController < AbstractRepositoryController
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
  before_action :login_required_redirect_for_public_repo
  before_action :add_models_repo_client_side_feature_flags

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    optional: true

  layout "repository_with_container"

  def self.react_bundle_name
    "github-models-repo"
  end

  def index
    all_models = params[:all_models] == "true"
    if request&.xhr?
      return render(json: models_repo.models(user: models_user, all_models: all_models).map(&:to_repository_model))
    end

    render_react_app(
      title: "Models · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models },
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
      },
      app_payload_generator: -> { # Keep in sync with `ModelRepoPayload` in ui/packages/github-models-repo/types.ts
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          enabled_features: {},
          canEdit: can_edit?,
          prompts: prompts,
          totalPrompts: GitHubModels::Prompt.for_repo(current_repository).count,
          restrictedModels: models_user.restricted_models,
          sampleActionsUrl: sample_actions_url,
          paidUsageBannerDismissed: user_dismissed_paid_notice?,
          current_user: {
            login: current_user&.display_login,
          },
          businessSlug: business_slug,
          compareModelsUrl: compare_models_url,
          onboardingVideoBannerDismissed: current_user&.dismissed_notice?(:github_models_onboarding_video_banner),
          userSettings: GitHubModels::Kv.get_user_repo_settings(current_user&.id, current_repository.id),
          isMarketplaceEnabled: GitHub.marketplace_enabled?,
          rateLimitLink: doc_urls[:rateLimit],
        }
      }
    )
  end

  def show
    if request&.xhr?
      slug = GitHubModels.domain.models.slug_for(registry: params[:registry], name: params[:model])
      model = GitHubModels.domain.models.find!(slug: slug)
      model_input_schema = model.to_schema
      getting_started = getting_started_table_of_contents(models_user.model_hash(model), model_input_schema)
      return render json: {
        gettingStarted: getting_started,
      }
    end

    render_404
  end

  private

  def sample_actions_url
    template_json = Actions::WorkflowTemplates.new(current_repository, current_user).get_by_id("automation/summary")
    if template_json.nil? # fall back to the docs URL if we can't find the template for some reason
      return helpers.docs_url(
        "github-models/integrating-ai-models-into-your-development-workflow",
        fragment: "using-ai-models-with-github-actions",
        ghec: GitHub.multi_tenant_enterprise?
      )
    end

    template = ::RepositoryActions::Onboarding::Template.new(template_json)
    new_file_path(current_repository.owner, current_repository, current_repository.default_branch, filename: template.default_file_name, workflow_template: template.id)
  end

  sig { returns T.nilable(String) }
  def compare_models_url
    repo_models = models_repo.models(user: models_user)

    first_available_model = repo_models.first
    return nil unless first_available_model

    second_available_model = repo_models.second || first_available_model

    registry = first_available_model.registry
    model = first_available_model.name
    compare_to = second_available_model.name
    models_playground_path(registry: registry, model: model, compare_to: compare_to)
  end

  def require_feature
    render_404 unless models_repo.models_enabled_for_repo?
  end

  # Can the current user edit or create prompts within the repository
  def can_edit?
    return false if current_repository.archived? || current_repository.locked_on_migration?
    return false unless logged_in?
    return false if T.must(current_user).must_verify_email?
    current_user_can_push?
  end

  sig { returns(T::Array[GitHubModels::Types::RepositoryPrompt]) }
  def prompts
    GitHubModels::Prompt.for_repo(current_repository)
                        .chronological
                        .limit(4)
                        .map(&:to_repo_prompt).as_json
  end
end
