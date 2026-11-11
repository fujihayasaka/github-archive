# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::OIDCConfigurationController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include Api::App::OIDCTemplateHelper
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :feature_flag_enabled?

  allow_verified_fetch only: [:update_custom_property_claims, :update_subject_claim, :check_template_validity]
  before_action :sudo_filter, only: [:update_custom_property_claims, :update_subject_claim]
  before_action :try_parse_json_params, only: [:update_custom_property_claims, :update_subject_claim, :check_template_validity]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Domain::Oidc,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    ApplicationRecord::Repositories,
    only: [:index, :search_properties, :update_custom_property_claims, :update_subject_claim]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsSettings::OIDCConfigurationController#update_custom_property_claims",
    "Orgs::ActionsSettings::OIDCConfigurationController#update_subject_claim"
  ]

  sig { returns(String) }
  def self.react_bundle_name
    "actions-oidc-configuration"
  end

  class OrganizationActionsOIDCConfigurationPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "organizationOidcConfigurationRoute"
    end

    sig { params(org: Organization, property_inclusions: T::Array[Actions::OIDCConfigurationHelper::CustomPropertyItem]).void }
    def initialize(org:, property_inclusions:)
      @claim_keys = OrganizationOIDCSubClaimTemplate.get_template_for_org(org.id)
      @property_inclusions = property_inclusions
      @enterprise = org.business
    end

    sig { override.returns(T.untyped) }
    def payload
      {
        subjectClaimKeys: @claim_keys.present? ? JSON.parse(@claim_keys.template) : nil,
        includedProperties: @property_inclusions,
        enterprise: @enterprise.present? ? { slug: @enterprise.slug, name: @enterprise.name } : nil
      }
    end
  end

  sig { void }
  def index
    add_client_feature_flag([:actions_oidc_custom_repo_properties], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_flag_enabled?(feature_name, default: false) || feature_enabled_globally_or_for_current_user_or_entity?(feature_name, organization)
    end

    property_inclusions = if FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, current_user, current_organization, current_organization.business, default: false)
      Actions::OIDCConfigurationHelper.get_included_repo_properties(current_organization)
    else
      []
    end

    payload = OrganizationActionsOIDCConfigurationPayload.new(
      org: current_organization,
      property_inclusions: property_inclusions
    )

    GitHub.dogstats.increment("oidc_config_ui.org.viewed")

    respond_with_react(
      payload:,
      title: "OIDC Configuration · #{current_organization.name}",
      layout: "layouts/settings/actions_org_react",
      page_data: { selected_link: :organization_actions_settings_oidc_configuration },
    )
  end

  sig { void }
  def search_properties # rubocop:disable GitHub/UseRestfulActions
    query = params[:q]
    render json: Actions::OIDCConfigurationHelper.search_repo_custom_properties(current_organization, query)
  end

  sig { void }
  def check_template_validity  # rubocop:disable GitHub/UseRestfulActions
    if params[:subjectClaimKeys].blank?
      return render json: { error: "Template must not be empty" }, status: :unprocessable_entity
    end

    if !params[:subjectClaimKeys].is_a?(Array)
      return render json: { error: "Invalid template format" }, status: :unprocessable_entity
    end

    validate_and_veto_sub_customization_template(claim_keys: params[:subjectClaimKeys], org: current_organization, enterprise: current_organization.business)

    head :ok
  rescue Api::App::OIDCTemplateHelper::InvalidTemplateError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def update_custom_property_claims # rubocop:disable GitHub/UseRestfulActions
    new_property_names = params[:includedProperties]

    if FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, current_user, current_organization, current_organization.business, default: false)
      if !new_property_names.nil?
        Actions::OIDCConfigurationHelper.update_included_repo_properties(current_organization, new_property_names)
        GitHub.dogstats.increment("oidc_config_ui.org.updated_custom_property_claims")
      end
    end

    head :ok
  rescue OIDC::RepoCustomPropertyInclusionHelper::PropertyNotFoundError, OIDC::RepoCustomPropertyInclusionHelper::LimitExceededError => ex
    render json: { error: ex.message }, status: 422
  end

  sig { void }
  def update_subject_claim # rubocop:disable GitHub/UseRestfulActions
    claim_keys = params[:subjectClaimKeys]

    # Template data validation. This might throw an exception
    validate_and_veto_sub_customization_template(claim_keys: claim_keys, org: current_organization, enterprise: current_organization.business)

    claim_keys = format_claim_keys_for_template(claim_keys)
    OrganizationOIDCSubClaimTemplate.create_or_update_template(current_organization.id, claim_keys.to_json)

    GitHub.dogstats.increment("oidc_config_ui.org.updated_sub_claim_template")

    head :ok
  rescue Api::App::OIDCTemplateHelper::InvalidTemplateError => e
    render json: { error: e.message }, status: 422
  end

  private

  sig { void }
  def feature_flag_enabled?
    render_404 unless FeatureFlag.vexi.enabled?(:actions_oidc_settings_ui, current_organization, current_organization.business, default: false)
  end
end
