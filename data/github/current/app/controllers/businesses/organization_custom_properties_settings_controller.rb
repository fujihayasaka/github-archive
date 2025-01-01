# typed: true
# frozen_string_literal: true

class Businesses::OrganizationCustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomPropertiesCore::Errors

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  before_action :check_feature_enabled

  allow_verified_fetch only: [:destroy, :check_property_usage, :create, :set_values]
  before_action :sudo_filter, only: [:destroy, :create, :set_values]
  before_action :try_parse_json_params, only: [:create, :set_values]

  def self.react_bundle_name
    "custom-properties-for-orgs"
  end

  javascript_bundle :settings
  layout "react_business"

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::OrganizationCustomPropertiesSettingsController#destroy",
    "Businesses::OrganizationCustomPropertiesSettingsController#create",
    "Businesses::OrganizationCustomPropertiesSettingsController#set_values",
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

  class BusinessCustomPropertiesListPayload < ReactPayload::Base
    include Orgs::CustomPropertiesHelper

    def route_id
      "businessCustomPropertiesSettingsRoute"
    end

    sig { params(business: Business, q: T.nilable(String), page: Integer).void }
    def initialize(business:, q: nil, page: 1)
      @results = Orgs.domain.custom_properties.search_definitions(business, q, page)
    end

    def payload
      {
        activeTab: "properties",
        definitions: definitions_payload(@results[:items]),
        pageCount: @results[:total_pages],
        totalCount: @results[:total_entries],
      }
    end
  end

  class BusinessCustomPropertiesDefinitionPayload < ReactPayload::Base
    include Orgs::CustomPropertiesHelper

    def route_id
      "businessPropertyDefinitionRoute"
    end

    sig do
      params(
        definition: T.nilable(CustomProperties::IPropertyDefinition),
        source_definitions: T::Array[CustomProperties::IPropertyDefinition]
      ).void
    end
    def initialize(definition:, source_definitions:)
      @definition = definition
      @source_definitions = source_definitions
    end

    def payload
      {
        definition: @definition ? definition_payload(@definition) : nil,
        propertyNames: @source_definitions.map(&:property_name)
      }
    end
  end

  class BusinessCustomPropertiesSetValuesPayload < ReactPayload::Base
    include Orgs::CustomPropertiesHelper

    PER_PAGE = 30

    def route_id
      "businessCustomPropertiesSettingsRoute"
    end

    sig { params(business: Business, user: User, q: T.nilable(String), page: Integer).void }
    def initialize(business:, user:, q: nil, page: 1)
      @org_results = business.filtered_organizations(viewer: user, query: q).paginate(page: page, per_page: PER_PAGE).to_a
      @definitions = Orgs.domain.custom_properties.get_definitions(business)

      org_properties = Orgs.domain.custom_properties.values_for_targets(@org_results, value_to_use: :manual, strip_nils: true)
      @orgs = @org_results.map do |org|
        {
          id: org.id,
          login: org.display_login,
          properties: org_properties[org],
        }
      end
    end

    def payload
      {
        activeTab: "set-values",
        definitions: definitions_payload(@definitions),
        pageCount: @org_results.total_pages,
        totalCount: @org_results.total_entries,
        orgs: @orgs,
      }
    end
  end

  def index
    payload = if params[:tab] == "set-values"
      BusinessCustomPropertiesSetValuesPayload.new(business: this_business, user: current_user, q: params[:q], page: current_page)
    else
      BusinessCustomPropertiesListPayload.new(business: this_business, q: params[:q], page: current_page)
    end

    respond_with_react(
      payload:,
      title: "Custom properties · #{this_business.name}",
      page_data: { selected_link: :business_organization_custom_properties_settings, sidebar: :organizations },
    )
  end

  def show
    if property_name = params[:property_name]
      definition = Orgs.domain.custom_properties.get_definition(this_business, property_name)
      return render_404 unless definition
    end

    definitions = Orgs.domain.custom_properties.get_definitions(this_business)

    respond_with_react(
      payload: BusinessCustomPropertiesDefinitionPayload.new(definition: definition, source_definitions: definitions),
      title: "Custom property · #{this_business.name}",
      page_data: { selected_link: :business_organization_custom_properties_settings, sidebar: :organizations },
    )
  end

  sig { void }
  def create
    begin
      definition = Orgs.domain.custom_properties.save_definition(
        this_business,
        property_name: params[:propertyName],
        value_type: params[:valueType],
        required: params[:required] || false,
        description: params[:description],
        default_value: params[:defaultValue],
        allowed_values: params[:allowedValues],
        values_editable_by: params[:valuesEditableBy],
        regex: params[:regex],
      )

      head :created
    rescue DefinitionLimitReachedError, InvalidDefinition, DefinitionDeletionAllowValueInUseError => ex
      render json: { error: ex.message }, status: 422
    rescue ArgumentError
      render json: { error: "Something went wrong." }, status: 422
    end
  end

  def destroy
    Orgs.domain.custom_properties.delete_definition(this_business, params[:property_name])
    head 200
  end

  sig { void }
  def set_values # rubocop:todo GitHub/UseRestfulActions
    payload = params.slice(:targetIds, :properties).permit!

    target_ids = T.cast(payload[:targetIds], T::Array[Integer])
    properties = T.cast(payload[:properties].to_h, T::Hash[String, CustomProperties::PropertyValue])

    orgs = this_business.organizations.where(id: target_ids)
    return head :not_found if target_ids - orgs.pluck(:id) != []

    begin
      Orgs.domain.custom_properties.set_properties_for(this_business, orgs.to_a, properties, actor: current_user)

      head :ok
    rescue CustomPropertiesCore::Errors::PropertyValidationError => error
      render json: { error: error.message }, status: 422
    end
  end

  def check_property_usage # rubocop:disable GitHub/UseRestfulActions
    property_name = params[:property_name]
    definition = Orgs.domain.custom_properties.get_definition(this_business, property_name)

    return render_404 unless definition

    render json: {
      count: Orgs.domain.custom_properties.property_usage_count(definition)
    }
  end

  private

  def check_feature_enabled
    render_404 unless Orgs.domain.custom_properties.feature_enabled?(this_business)
  end
end
