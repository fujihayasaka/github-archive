# typed: strict
# frozen_string_literal: true

class Businesses::CustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomProperties::Errors

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_properties_enabled

  allow_verified_fetch only: [:destroy, :create]
  before_action :sudo_filter, only: [:destroy, :create]
  before_action :try_parse_json_params, only: [:create]

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "custom-properties"
  end

  javascript_bundle :settings

  layout "react_business"

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
    ApplicationRecord::Repositories,
  only: [:index, :show, :check_usage]

  DEFINITIONS_PER_PAGE = 30

  sig { void }
  def index
    properties_list_enabled = CustomProperties::Public.enterprise_properties_list_enabled?(this_business)
    add_client_feature_flag([:enterprise_custom_properties_list]) { properties_list_enabled }
    add_client_feature_flag([:enterprise_custom_properties_promotion]) do
      this_business.feature_enabled?(:enterprise_custom_properties_promotion)
    end

    results = if properties_list_enabled
      Search::Definitions::MysqlSearch.search(this_business, params[:q], current_page)
    else
      definitions = definitions_manager.get_definitions

      {
        items: definitions,
        total_entries: definitions.size,
        total_pages: 1,
      }
    end

    payload = {
      definitions: definitions_payload(results[:items]),
      pageCount: results[:total_pages],
      totalCount: results[:total_entries],
      ownDefinitionsCount: definitions_manager.own_definitions_count,
    }

    render_react_app(
      ssr: false,
      payload:,
      title: "Custom properties · #{this_business.name}",
      page_data: { selected_link: :business_custom_properties_settings },
    )
  end

  sig { void }
  def show
    add_client_feature_flag([:enterprise_custom_properties_list]) do
      CustomProperties::Public.enterprise_properties_list_enabled?(this_business)
    end
    add_client_feature_flag([:enterprise_custom_properties_promotion]) do
      this_business.feature_enabled?(:enterprise_custom_properties_promotion)
    end

    name = params[:property_name]
    definition = name ? definitions_manager.get_definition(name) : nil

    title = "Custom properties · #{this_business.name} · #{definition ? "#{definition.property_name}" : "Create custom property"}"

    render_react_app(
      ssr: false,
      payload: {
        definition: definition ? definition_payload(definition) : nil,
        propertyNames: definitions_manager.get_definitions.map { |d| d.property_name },
      },
      title: title,
      page_data: { selected_link: :business_custom_properties_settings },
    )
  end

  sig { void }
  def create
    payload = params.slice(
      :propertyName,
      :valueType,
      :required,
      :description,
      :defaultValue,
      :allowedValues,
      :valuesEditableBy,
      :regex,
    ).permit!

    begin
      definition = definitions_manager.save_definition(
        property_name: payload[:propertyName],
        value_type: payload[:valueType],
        required: payload[:required] || false,
        description: payload[:description],
        default_value: payload[:defaultValue],
        allowed_values: payload[:allowedValues],
        values_editable_by: payload[:valuesEditableBy],
        regex: payload[:regex],
      )
      render json: definition_payload(definition), status: :created
    rescue DefinitionLimitReachedError, InvalidDefinition, DefinitionDeletionAllowValueInUseError => ex
      render json: { error: ex.message }, status: 422
    rescue ArgumentError
      render json: { error: "Something went wrong." }, status: 422
    end
  end

  sig { void }
  def check_usage # rubocop:todo GitHub/UseRestfulActions
    name = params[:property_name]

    definition = definitions_manager.get_definition(name)

    return render_404 unless definition

    render json: {
      propertyName: name,
      repositoriesCount: CustomProperties::Public.property_usage(definition)[:repositories_count],
      propertyConsumerUsages: [],
    }
  end

  sig { void }
  def destroy
    definitions_manager.delete_definition(params[:property_name])

    head 200
  end

  private

  sig { void }
  def check_business_properties_enabled
    render_404 unless CustomProperties::Public.enterprise_properties_enabled?(this_business)
  end

  sig { returns(CustomPropertiesBusinessDefinitionsManager) }
  memoize def definitions_manager
    CustomProperties::Public.business_definitions_manager(this_business)
  end
end
