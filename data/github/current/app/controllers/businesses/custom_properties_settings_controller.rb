# typed: strict
# frozen_string_literal: true

class Businesses::CustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomPropertiesCore::Errors

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  allow_verified_fetch only: [:destroy, :create]
  before_action :sudo_filter, only: [:destroy, :create]
  before_action :try_parse_json_params, only: [:create]

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
    add_client_feature_flag([:repos_list_show_filter_dialog])

    # Nil indicates initial page load, otherwise it contains the user's search.
    # We only want to fallback to default on initial page load.
    current_q = params[:q].nil? ? "managed-by:enterprise" : params[:q]

    results = Repositories.domain.custom_properties.search_definitions(this_business, current_q, current_page)
    definitions_count = Repositories.domain.custom_properties.get_own_definitions(this_business).size

    payload = {
      definitions: definitions_payload(results[:items]),
      pageCount: results[:total_pages],
      totalCount: results[:total_entries],
      ownDefinitionsCount: definitions_count,
      currentQ: current_q,
    }

    render_react_app(
      disable_ssr: true,
      payload:,
      title: "Custom properties · #{this_business.name}",
      page_data: { selected_link: :business_custom_properties_settings, sidebar: custom_properties_sidebar },
    )
  end

  sig { void }
  def show
    name = params[:property_name]

    definition = name ? Repositories.domain.custom_properties.get_definition(this_business, name) : nil

    title = "Custom properties · #{this_business.name} · #{definition ? "#{definition.property_name}" : "Create custom property"}"

    definitions = Repositories.domain.custom_properties.get_definitions(this_business)

    render_react_app(
      disable_ssr: true,
      payload: {
        definition: definition ? definition_payload(definition) : nil,
        propertyNames: definitions.map { |d| d.property_name },
        propertiesLimits: properties_limits_payload(Repositories.domain.custom_properties.limits(this_business)),
      },
      title: title,
      page_data: { selected_link: :business_custom_properties_settings, sidebar: custom_properties_sidebar },
    )
  end

  sig { void }
  def create
    payload = params.slice(
      :propertyName,
      :valueType,
      :required,
      :requireExplicitValues,
      :description,
      :defaultValue,
      :allowedValues,
      :valuesEditableBy,
      :regex,
    ).permit!

    begin
      definition = Repositories.domain.custom_properties.save_definition(
        this_business,
        property_name: payload[:propertyName],
        value_type: payload[:valueType],
        required: payload[:required] || false,
        require_explicit_values: payload[:requireExplicitValues] || false,
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
    property_name = params[:property_name]

    definition = Repositories.domain.custom_properties.get_definition(this_business, property_name)
    return render_404 unless definition

    target_usage_count = Repositories.domain.custom_properties.property_target_reference_count(definition)

    response_payload = {
      propertyName: property_name,
      count: target_usage_count
    }

    if FeatureFlag.vexi.enabled?(:custom_property_usages_ui, this_business, current_user, default: false)
      resource_usages = Repositories.domain.custom_properties.get_all_usages_for(this_business, property_name)
      response_payload[:resourceUsages] = resource_usages.map(&:resource_type).uniq
    end

    render json: response_payload
  end

  sig { void }
  def destroy
    Repositories.domain.custom_properties.delete_definition(this_business, params[:property_name])
    head 200
  end

  private

  sig { returns(Symbol) }
  def custom_properties_sidebar
    if FeatureFlag.vexi.enabled?("glc_ia_enterprise_organizations_sidebar", current_user, this_business, default: false)
      :organizations
    else
      :policies
    end
  end
end
