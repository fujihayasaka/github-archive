# typed: strict
# frozen_string_literal: true

require "react_payload"

class Repos::CodeQuality::SettingsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::DefaultSetupHelper
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_feature_code_quality_available
  before_action :manage_code_quality_permission_required
  before_action :writable_repository_required
  before_action :try_parse_json_params, only: [:update]

  class SettingsPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualitySettingsRoute"
    end

    sig do
      params(
        owner: String,
        repo: String,
        is_default_setup_enabled: T::Boolean,
        is_code_quality_enabled: T::Boolean,
        is_default_setup_update_in_progress: T::Boolean,
        languages: T::Array[T::Hash[String, T.untyped]],
        default_branch: String,
        next_scheduled_run_at: T.nilable(Time),
        runner_label: T.nilable(String),
        about_codeql_docs_url: String,
        about_actions_billing_docs_url: String,
      )
      .void
    end
    def initialize(
      owner:,
      repo:,
      is_default_setup_enabled:,
      is_code_quality_enabled:,
      is_default_setup_update_in_progress:,
      languages:,
      default_branch:,
      next_scheduled_run_at:,
      runner_label:,
      about_codeql_docs_url:,
      about_actions_billing_docs_url:
    )
      @owner = T.let(owner, String)
      @repo = T.let(repo, String)
      @is_default_setup_enabled = T.let(is_default_setup_enabled, T::Boolean)
      @is_code_quality_enabled = T.let(is_code_quality_enabled, T::Boolean)
      @is_default_setup_update_in_progress = T.let(is_default_setup_update_in_progress, T::Boolean)
      @languages = T.let(languages, T::Array[T::Hash[String, T.untyped]])
      @default_branch = T.let(default_branch, String)
      @next_scheduled_run_at = T.let(next_scheduled_run_at, T.nilable(Time))
      @runner_label = T.let(runner_label, T.nilable(String))
      @about_codeql_docs_url = T.let(about_codeql_docs_url, String)
      @about_actions_billing_docs_url = T.let(about_actions_billing_docs_url, String)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        owner: @owner,
        repo: @repo,
        isDefaultSetupEnabled: @is_default_setup_enabled,
        isCodeQualityEnabled: @is_code_quality_enabled,
        isDefaultSetupUpdateInProgress: @is_default_setup_update_in_progress,
        languages: @languages,
        defaultBranch: @default_branch,
        nextScheduledRunAt: @next_scheduled_run_at,
        runnerLabel: @runner_label,
        aboutCodeQLDocsURL: @about_codeql_docs_url,
        aboutActionsBillingDocsURL: @about_actions_billing_docs_url,
      }
    end
  end

  # `update` does have dependencies too, but there aren't currently Rails tests for it
  # so we don't have a way of keeping that list up to date. Hence only declaring the
  # dependencies for `edit` here.
  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:edit]

  sig { void }
  def edit
    respond_with_react(
      payload: payload,
      app_name: "code-quality",
      title: "Settings · Code quality · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :code_quality,
      },
      layout: "layouts/repository_settings",
    )
  end

  sig { void }
  def update
    manager = SecurityProduct::ServiceManager.new(current_repository)
    result = if params[:enabled]
      manager.toggle_services(current_user, services_to_enable: [:code_quality])
    elsif params[:enabled] == false
      manager.toggle_services(current_user, services_to_disable: [:code_quality])
    end

    if result&.error?
      render json: { message: CodeQualityEnablement.error_to_message(result.error) }, status: :unprocessable_entity
    else
      render json: payload.payload.as_json
    end
  end

  private

  sig { returns(CodeScanning::AutoCodeql) }
  memoize def auto_codeql
    CodeScanning::AutoCodeql.new(current_repository)
  end

  sig { returns(CodeQualityEnablement) }
  memoize def code_quality_enablement
    CodeQualityEnablement.new(current_repository)
  end

  sig { returns(Repos::CodeQuality::SettingsController::SettingsPayload) }
  def payload
    SettingsPayload.new(
      owner: current_repository.owner.display_login,
      repo: current_repository.name,
      is_default_setup_enabled: auto_codeql.enabled?,
      is_code_quality_enabled: code_quality_enablement.enabled?,
      is_default_setup_update_in_progress: auto_codeql.updating? || auto_codeql.enabling?,
      languages: auto_codeql.configuration.languages.map do |language|
        {
          name: auto_codeql_language_name(language),
          color: auto_codeql_language_color(language),
        }
      end,
      default_branch: current_repository.default_branch,
      next_scheduled_run_at: auto_codeql.next_scheduled_run_at,
      runner_label: auto_codeql.configuration.runner_label,
      about_codeql_docs_url: helpers.docs_url("code-security/about-code-scanning-with-codeql", fragment: "about-codeql"),
      about_actions_billing_docs_url: helpers.docs_url("billing/about-billing-for-github-actions"),
    )
  end

  # Technically this returns a nilable boolean, but you shouldn't use the return value
  sig { void }
  def ensure_feature_code_quality_available
    render_404 unless CodeQuality.available?(current_repository)
  end

  sig { void }
  def manage_code_quality_permission_required
    if current_repository.owner&.organization?
      render_access_denied unless CodeQualityManagementRepositoryPermissions.new(current_repository).code_quality_manageable_by?(current_user)
    else
      ensure_admin_access
    end
  end
end
