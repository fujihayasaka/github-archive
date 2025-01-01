# typed: true
# frozen_string_literal: true

class Orgs::OrganizationCustomPropertiesSettingsController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include CustomPropertiesCore::Errors

  before_action :login_required

  before_action :ensure_current_organization
  before_action :check_org_business_owned

  before_action :check_edit_permissions, only: [:update, :index]
  before_action :check_feature_enabled

  allow_verified_fetch only: [:update]
  before_action :sudo_filter, only: [:update]
  before_action :try_parse_json_params, only: [:update]

  def self.react_bundle_name
    "custom-properties-for-orgs"
  end

  layout "organization_settings"

  stylesheet_bundle :settings
  javascript_bundle :settings

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::OrganizationCustomPropertiesSettingsController#update",
  ]

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories

  class OrganizationCustomPropertiesSetValuesPayload < ReactPayload::Base
    include Orgs::CustomPropertiesHelper

    def route_id
      "organizationCustomPropertiesSettingsRoute"
    end

    sig { params(current_organization: Organization, actor: User).void }
    def initialize(current_organization:, actor:)
      # Business presence is checked in the before_action
      business = T.must(current_organization.business)
      @current_organization = current_organization
      @definitions = Orgs.domain.custom_properties.get_definitions(business)

      has_enterprise_permission = Authz.domain.check_allowed(actor, :edit_enterprise_custom_properties_for_organizations, business)

      @editable_definitions = if has_enterprise_permission
        @definitions
      else
        # User has the org level edit permission; restrict to definitions editable by org actors
        @definitions.select do |definition|
          T.cast(definition, OrganizationCustomPropertyDefinition).enterprise_and_org_actors?
        end
      end

      @properties = Orgs.domain.custom_properties.values_for_targets(
        [current_organization],
        value_to_use: :manual,
        strip_nils: true
      ).dig(current_organization)
    end

    def payload
      {
        definitions: definitions_payload(@definitions),
        editableProperties: @editable_definitions.map(&:property_name),
        currentTarget: {
          id: @current_organization.id,
          login: @current_organization.display_login,
          properties: @properties
        }
      }
    end
  end

  sig { void }
  def index
    payload = OrganizationCustomPropertiesSetValuesPayload.new(
      current_organization: current_organization,
      actor: current_user
    )

    respond_with_react(
      payload:,
      title: "Settings · Organization custom properties · #{current_organization.name}",
      page_data: { selected_link: :custom_properties_for_orgs },
    )
  end

  sig { void }
  def update
    return head :bad_request unless params[:properties]

    payload = params.slice(:properties).permit!
    properties = T.cast(payload[:properties].to_h, T::Hash[String, CustomProperties::PropertyValue])

    begin
      Orgs.domain.custom_properties.set_properties_for(current_organization.business, [current_organization], payload[:properties].to_h, actor: current_user)
      head :ok
    rescue CustomPropertiesCore::Errors::EditPropertyPermissionError => error
      render json: { error: error.full_message }, status: 403
    rescue CustomPropertiesCore::Errors::PropertyValidationError => error
      render json: { error: error.message }, status: 422
    end
  end

  private

  def check_edit_permissions
    if FeatureFlag.vexi.enabled?(:custom_properties_for_orgs_fgp, current_organization.business, default: false)
      render_404 unless Authz.domain.check_allowed(current_user, :edit_custom_properties_for_organizations, current_organization)
    else
      organization_admin_required
    end
  end

  def check_org_business_owned
    render_404 if current_organization.business.nil?
  end

  def check_feature_enabled
    render_404 unless Orgs.domain.custom_properties.feature_enabled?(current_organization)
  end
end
