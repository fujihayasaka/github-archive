# typed: true
# frozen_string_literal: true

module GitHubModels::RepositoryPromptsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include BranchesHelper
  include GitHub::Memoizer
  include WebCommitControllerMethods
  include GitHubModels::RenderDependency
  include RepositoriesHelper

  abstract!

  requires_ancestor { AbstractRepositoryController }

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig do
    params(
      ref: T.nilable(String),
      path: T.nilable(String),
      content: T.nilable(String),
      head_prompt_content: T.nilable(String),
      create: T::Boolean
    ).void
  end
  def render_model_prompt(ref:, path:, content:, head_prompt_content: nil, create: false)
    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    payload = GitHubModels::Payloads::Prompt.new(
      models_user: models_user,
      improved_sys_prompt_model: get_improved_prompt_model,
      prompt: content,
      prompt_path: path,
      prompt_ref: ref,
      repository: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      inference_url: inference_url,
      commit_info: get_commit_info(tree_name: tree_name, tree_type: tree_type, commit_sha: commit_sha, create: create),
      can_edit: can_edit?,
      paid_usage_banner_dismissed: user_dismissed_paid_notice?,
      business_slug: business_slug,
      user_settings: GitHubModels::Kv.get_user_repo_settings(current_user&.id, current_repository.id),
      rate_limit_link: doc_urls[:rateLimit],
    ).call

    render_react_app(
      app_payload_generator: -> {
        {
          current_user: {
            login: current_user&.display_login,
            name: current_user&.name,
            avatarUrl: current_user&.primary_avatar_url(80),
            path: user_path(current_user)
          },
          payload: payload, # We want to re-use this for different pages which don't have route specific data
        }
      },

      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
        title: "#{create ? "New prompt" : path} · #{current_repository.name_with_display_owner}",
        stafftools: stafftools_models_path,
        selected_link: :repo_models,
      },
      disable_ssr: true,
    )
  end

  private

  # Can the current user edit or create prompts within the repository
  sig { returns T::Boolean }
  def can_edit?
    return false if current_repository.archived? || current_repository.locked_on_migration?
    return false unless logged_in?
    return false if T.must(current_user).must_verify_email?
    current_user_can_push?
  end

  sig { returns(String) }
  def inference_url
    if can_edit?
      models_user.playground_url(org: current_repository.organization)
    else
      models_user.playground_url
    end
  end

  sig do
    params(
      tree_name: T.nilable(String),
      tree_type: T.nilable(String),
      commit_sha: T.nilable(String),
      create: T::Boolean
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def get_commit_info(tree_name:, tree_type:, commit_sha:, create:)
    branch = tree_name
    file_save_path = file_save_path(current_repository.owner, current_repository, tree_name, path_string)
    file_create_path = blob_create_path(path_string, tree_name, current_repository)

    url = create ? file_create_path : file_save_path
    authenticity_token = create ? authenticity_token_for(file_create_path) : authenticity_token_for(file_save_path)
    web_commit_info = web_commit_info(current_repository.refs[tree_name]&.target_oid, url, branch)

    {
      refInfo: {
        name: tree_name,
        listCacheKey: ref_list_cache_key,
        canEdit: true,
        refType: tree_type,
        currentOid: commit_sha
      },
      webCommitInfo: web_commit_info,
      path: path_string,
      fileSaveAuthenticityToken: authenticity_token
    }
  end

  sig { returns GitHubModels::Repository }
  memoize def models_repo
    GitHubModels::Repository.new(repository: current_repository)
  end

  sig { void }
  def require_feature
    render_404 unless models_repo.models_enabled_for_repo?
  end

  sig { void }
  def require_can_edit_repository
    redirect_to(repo_models_path(current_repository.owner, current_repository)) unless can_edit?
  end

  sig { void }
  def add_models_repo_client_side_feature_flags
    add_client_feature_flag([
      :github_models_scheduled_hydro_events,
    ])
  end

  sig { returns(T.nilable(Business)) }
  memoize def business
    current_repository.business
  end

  sig { returns(T.nilable(String)) }
  def business_slug
    business = self.business
    return if business.nil? || business.models_billing_enabled?
    business.slug
  end

  sig { returns(T::Boolean) }
  def user_dismissed_paid_notice?
    return true unless current_user
    return true if current_repository.archived?

    business = self.business

    # If business is present and models billing is enabled, still want to show banner at org level if models billing is not enabled in org
    can_access_billing_settings = if business && !business.models_billing_enabled?
      business.adminable_by?(current_user) && business.can_show_models_billing?
    elsif !current_repository.owner.can_show_models_billing?
      false
    elsif current_repository.in_organization?
      current_repository.owner.adminable_by?(current_user)
    elsif current_repository.owner.is_enterprise_managed?
      false
    else
      current_repository.owner == current_user
    end

    billing_enabled = if business && !business.models_billing_enabled?
      false
    else
      current_repository.owner.models_billing_enabled?
    end

    if !billing_enabled && can_access_billing_settings
      return T.must(current_user).dismissed_repository_notice?("github_models_paid_usage_banner_repo", repository_id: current_repository.id)
    end

    true
  end
end
