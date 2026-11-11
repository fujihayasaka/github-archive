# typed: true
# frozen_string_literal: true

class Businesses::Actions::OIDCConfigurationController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Actions::LargerRunnersHelper

  before_action :login_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  allow_verified_fetch only: [:update_custom_property_claims, :update_issuer_claim]
  before_action :sudo_filter, only: [:update_custom_property_claims, :update_issuer_claim]
  before_action :try_parse_json_params, only: [:update_custom_property_claims, :update_issuer_claim]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Domain::Oidc,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::ActionsEnvironments,
    only: [:index, :search_properties, :update_custom_property_claims, :update_issuer_claim]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::Actions::OIDCConfigurationController#update_custom_property_claims",
    "Businesses::Actions::OIDCConfigurationController#update_issuer_claim",
  ]

  sig { returns(String) }
  def self.react_bundle_name
    "actions-oidc-configuration"
  end

  class EnterpriseActionsOIDCConfigurationPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "enterpriseOidcConfigurationRoute"
    end

    sig do
      params(
        include_enterprise_slug: T::Boolean,
        property_inclusions: T::Array[Actions::OIDCConfigurationHelper::CustomPropertyItem],
        property_count: Integer,
      ).void
    end
    def initialize(include_enterprise_slug:, property_inclusions:, property_count:)
      @include_enterprise_slug = include_enterprise_slug
      @property_inclusions = property_inclusions
      @property_count = property_count
    end

    sig { override.returns(T.untyped) }
    def payload
      {
        includeEnterpriseSlugInIssuer: @include_enterprise_slug,
        includedProperties: @property_inclusions,
        propertyCount: @property_count,
      }
    end
  end

  sig { void }
  def index
    add_client_feature_flag([:actions_oidc_custom_repo_properties])

    issuer_policy = EnterpriseOIDCIssuerUrlCustomisation.get_issuer_policy(this_business.id)
    properties = Actions::OIDCConfigurationHelper.fetch_repo_properties_summary(this_business, current_user)

    payload = EnterpriseActionsOIDCConfigurationPayload.new(
      include_enterprise_slug: issuer_policy&.include_enterprise_name || false,
      property_inclusions: properties[:inclusions],
      property_count: properties[:count]
    )

    GitHub.dogstats.increment("oidc_config_ui.enterprise.viewed")

    respond_with_react(
      payload:,
      title: "OIDC Configuration · #{this_business.name}",
      layout: "layouts/settings/enterprise_actions_settings_react",
      page_data: { selected_link: :business_actions_settings_oidc_configuration, sidebar: :policies },
      layout_locals_generator: -> { { should_display_custom_images_tab: is_custom_images_enabled?(entity: this_business) } },
    )
  end

  sig { void }
  def search_properties # rubocop:disable GitHub/UseRestfulActions
    query = params[:q]
    render json: Actions::OIDCConfigurationHelper.search_repo_custom_properties(this_business, query)
  end

  sig { void }
  def update_custom_property_claims # rubocop:disable GitHub/UseRestfulActions
    if FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, current_user, this_business, default: false)
      new_property_names = params[:includedProperties]
      if !new_property_names.nil?
        Actions::OIDCConfigurationHelper.update_included_repo_properties(this_business, new_property_names)
        GitHub.dogstats.increment("oidc_config_ui.enterprise.updated_custom_property_claims")
      end
    end

    head :ok
  rescue OIDC::RepoCustomPropertyInclusionHelper::PropertyNotFoundError, OIDC::RepoCustomPropertyInclusionHelper::LimitExceededError => ex
    render json: { error: ex.message }, status: 422
  end

  sig { void }
  def update_issuer_claim # rubocop:disable GitHub/UseRestfulActions
    include_enterprise_slug = params[:includeEnterpriseSlugInIssuer]
    if !include_enterprise_slug.nil?
      EnterpriseOIDCIssuerUrlCustomisation.update_issuer_policy(this_business.id, include_enterprise_slug)
      GitHub.dogstats.increment("oidc_config_ui.enterprise.updated_issuer_claim")
    end

    head :ok
  end
end
