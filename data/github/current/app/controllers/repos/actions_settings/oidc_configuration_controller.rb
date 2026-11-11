# typed: true
# frozen_string_literal: true

class Repos::ActionsSettings::OIDCConfigurationController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include Api::App::OIDCTemplateHelper
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :ensure_actions_settings_access

  allow_verified_fetch only: [:update, :check_template_validity]
  before_action :sudo_filter, only: [:update]
  before_action :try_parse_json_params, only: [:update, :check_template_validity]

  depends_on_clusters ApplicationRecord::Domain::Oidc,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::Authnd,
    only: [:index, :update]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::ActionsSettings::OIDCConfigurationController#update"
  ]

  sig { returns(String) }
  def self.react_bundle_name
    "actions-oidc-configuration"
  end

  class RepositoryActionsOIDCConfigurationPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repositoryOidcConfigurationRoute"
    end

    sig { params(repo: Repository, immutable_subject_enabled: T::Boolean).void }
    def initialize(repo:, immutable_subject_enabled: false)
      configuration = RepositoryActionsOIDCConfig.get_configurations(repo.id)

      @custom_sub_disabled = configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED]
      @claim_keys = configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE]

      # Load org template lazily and reuse across both the claim-key fallback and the immutable-subject paths.
      org_template = nil
      if !@claim_keys.present? && !@custom_sub_disabled.nil? && !@custom_sub_disabled
        org_template = OrganizationOIDCSubClaimTemplate.get_template_for_org(repo.organization_id)
        @claim_keys = org_template.present? ? org_template.template : []
      end

      @immutable_subject_enabled = immutable_subject_enabled
      if @immutable_subject_enabled
        repo_setting = configuration[RepositoryActionsOIDCConfig::KEY_USE_IMMUTABLE_SUBJECT]
        if repo_setting.nil?
          # No repo-level opinion — fall back to org template.
          org_template ||= OrganizationOIDCSubClaimTemplate.get_template_for_org(repo.organization_id)
          @use_immutable_subject = org_template&.use_immutable_subject || false
        else
          # Repo-level setting (true or false) always wins over the org default.
          @use_immutable_subject = repo_setting
        end

        @sub_claim_prefix = RepositoryActionsOIDCConfig.sub_claim_prefix(repo)
        @immutable_sub_claim_prefix = RepositoryActionsOIDCConfig.immutable_sub_claim_prefix(repo)
        @is_immutable_sub_claim_auto_enabled = RepositoryActionsOIDCConfig.auto_enabled?(repo)
      end
    end

    sig { override.returns(T.untyped) }
    def payload
      base = {
        subjectClaimKeys: @claim_keys.present? ? JSON.parse(@claim_keys) : nil,
        useDefaultTemplate: @custom_sub_disabled.nil? || @custom_sub_disabled.present?,
        showImmutableSubject: @immutable_subject_enabled,
      }
      if @immutable_subject_enabled
        base.merge!(
          useImmutableSubject: @use_immutable_subject,
          subClaimPrefix: @sub_claim_prefix,
          immutableSubClaimPrefix: @immutable_sub_claim_prefix,
          isImmutableSubClaimAutoEnabled: @is_immutable_sub_claim_auto_enabled,
        )
      end
      base
    end
  end

  sig { void }
  def index
    payload = RepositoryActionsOIDCConfigurationPayload.new(repo: current_repository, immutable_subject_enabled: immutable_subject_enabled?)

    GitHub.dogstats.increment("oidc_config_ui.repo.viewed")

    respond_with_react(
      payload:,
      title: "OIDC Configuration",
      layout: "layouts/repository_settings",
      page_data: { selected_link: :repository_actions_settings_oidc_configuration },
    )
  end

  sig { void }
  def update
    use_default = params[:useDefaultTemplate]
    unless [true, false].include?(use_default)
      render json: { error: "Default template must be a boolean" }, status: :unprocessable_entity
      return
    end

    claim_keys = params[:subjectClaimKeys]

    begin
      configuration = construct_configuration_from_inputs(claim_keys:, use_default:, repo: current_repository)

      if params.key?(:useImmutableSubject) && immutable_subject_enabled?
        use_immutable = params[:useImmutableSubject]
        if [true, false].include?(use_immutable)
          configuration[RepositoryActionsOIDCConfig::KEY_USE_IMMUTABLE_SUBJECT] = use_immutable
        end
      end

      RepositoryActionsOIDCConfig.update_configurations(current_repository.id, configuration)

      GitHub.dogstats.increment("oidc_config_ui.repo.updated_sub_claim_template")

      head :ok
    rescue Api::App::OIDCTemplateHelper::InvalidTemplateError => e
      render json: { error: e.message }, status: 422
    end
  end

  sig { void }
  def check_template_validity  # rubocop:disable GitHub/UseRestfulActions
    if params[:subjectClaimKeys].blank?
      return render json: { error: "Template must not be empty" }, status: :unprocessable_entity
    end

    if !params[:subjectClaimKeys].is_a?(Array)
      return render json: { error: "Invalid template format" }, status: :unprocessable_entity
    end

    validate_and_veto_sub_customization_template(claim_keys: params[:subjectClaimKeys], org:  current_repository.organization, enterprise: current_repository.organization&.business)

    head :ok
  rescue Api::App::OIDCTemplateHelper::InvalidTemplateError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  sig { returns(T::Boolean) }
  def immutable_subject_enabled?
    FeatureFlag.vexi.enabled?(:actions_oidc_immutable_subject_claim, current_repository, current_repository.owner, default: false)
  end
end
