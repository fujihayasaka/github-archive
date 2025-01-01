# typed: strict
# frozen_string_literal: true

class Businesses::CustomPropertiesSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper
  include CustomProperties::Errors

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
    add_client_feature_flag([:repos_list_show_filter_dialog, :custom_property_definitions_required_filter])

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
      page_data: { selected_link: :business_custom_properties_settings, sidebar: :policies },
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
      },
      title: title,
      page_data: { selected_link: :business_custom_properties_settings, sidebar: :policies },
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
      definition = Repositories.domain.custom_properties.save_definition(
        this_business,
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

    definition = Repositories.domain.custom_properties.get_definition(this_business, name)

    return render_404 unless definition

    render json: {
      propertyName: name,
      repositoriesCount: Repositories.domain.custom_properties.property_usage(definition)[:repositories_count],
    }
  end

  sig { void }
  def destroy
    Repositories.domain.custom_properties.delete_definition(this_business, params[:property_name])
    head 200
  end
end
