# typed: strict
# frozen_string_literal: true

class Orgs::CustomPropertiesSettingsController < Orgs::Controller
  include ReactHelper
  include Orgs::CustomPropertiesHelper
  include Orgs::RepoListPayloadHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Repos::ListHelper
  include CustomProperties::Errors

  allow_verified_fetch only: [:create, :destroy, :check_usage, :update_repos_properties]
  before_action :ensure_trade_restrictions_allows_org_settings_access

  before_action :org_custom_properties_definitions_manager_only, only: [:show, :create, :destroy]
  before_action :org_custom_properties_manager_or_editor_only, only: [
    :index,
    :list_repos_property_values,
    :check_usage,
  ]
  before_action :redirect_to_tab, only: [:index]
  before_action :sudo_filter, only: [:update_repos_properties, :destroy, :create]
  before_action :try_parse_json_params, only: [:update_repos_properties, :create]

  sig { returns(String) }
  def self.react_bundle_name
    "custom-properties"
  end

  layout "organization_settings"

  stylesheet_bundle :settings
  javascript_bundle :settings

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
    ApplicationRecord::Spokes,
    only: [:index, :show, :check_usage, :list_repos_property_values]

  REPO_LIST_PAGE_LIMIT = 30
  DEFINITIONS_PER_PAGE = 30

  sig { void }
  def index
    add_client_feature_flag([:custom_properties_regex], entity: current_organization)
    add_client_feature_flag([:boolean_property_value_toggle])
    add_client_feature_flag([:repos_list_show_filter_dialog])
    add_client_feature_flag([:custom_properties_edit_modal])

    properties_list_enabled = CustomProperties::Public.enterprise_properties_list_enabled?(current_organization)
    add_client_feature_flag([:enterprise_custom_properties_list]) do
      properties_list_enabled
    end

    definitions = definitions_manager.get_definitions

    base_payload = {
      business: business_info,
      permissions: user_permissions,
      ownDefinitionsCount: definitions_manager.own_definitions_count,
    }

    page_payload = if params[:tab] == "set-values"
      {
        activeTab: "set-values",
        **base_payload,
        **list_repos_property_values_payload,
        definitions: definitions_payload(definitions),
      }
    else
      {
        activeTab: "properties",
        **base_payload,
        **definitions_list_payload(definitions, properties_list_enabled:),
      }
    end

    render_react_app(
      ssr: true,
      payload: page_payload,
      title: "Settings · Custom properties · #{current_organization.name}",
      page_data: { selected_link: :organization_custom_properties },
    )
  end

  sig { void }
  def show
    name = params[:property_name]

    definitions = definitions_manager.get_definitions
    definition = definitions.find { |d| d.property_name == name }

    return redirect_to org_custom_properties_path(current_organization) if definition.nil? && name.present?

    title = "Settings · Custom properties · #{current_organization.name} · #{definition ? "#{definition.property_name}" : "Create custom property"}"
    add_client_feature_flag([:custom_properties_regex], entity: current_organization)
    add_client_feature_flag([:enterprise_custom_properties_list]) do
      CustomProperties::Public.enterprise_properties_list_enabled?(current_organization)
    end

    render_react_app(
      ssr: true,
      payload: {
        definition: definition ? definition_payload(definition) : nil,
        business: business_info,
        propertyNames: definitions.map { |d| d.property_name },
        canManageBusiness: can_manage_business?,
      },
      title: title,
      page_data: { selected_link: :organization_custom_properties },
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
  def destroy
    definitions_manager.delete_definition(params[:property_name])

    head 200
  end

  sig { void }
  def update_repos_properties # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_organization

    payload = params.slice(:repoIds, :properties).permit!

    repo_ids = T.cast(payload[:repoIds], T::Array[Integer])
    properties = T.cast(payload[:properties].to_h, T::Hash[String, String])

    repos = current_organization.repositories.where(id: repo_ids).to_a
    return head :not_found if repo_ids - repos.pluck(:id) != []

    property_names = properties.keys
    return head :not_found if property_names - definitions_manager.get_definitions.pluck(:property_name) != []

    GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.batch_size", repos.size)
    GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.property_names_size", properties.size)

    begin
      GitHub.dogstats.distribution_time("custom_properties_settings.update_repos_properties.time") do
        values_manager.set_properties_for(repos, properties, actor: current_user)
      end

      head :ok
    rescue CustomProperties::Errors::EditPropertyPermissionError => error
      render json: { error: error.full_message }, status: 403
    rescue CustomProperties::Errors::PropertyValidationError => error
      render json: { error: error.message }, status: 422
    end
  end

  sig { void }
  def list_repos_property_values # rubocop:todo GitHub/UseRestfulActions
    render json: list_repos_property_values_payload
  end

  sig { void }
  def check_usage # rubocop:todo GitHub/UseRestfulActions
    name = params[:property_name]

    definition = definitions_manager.get_definition(name)

    return render_404 unless definition

    render json: {
      propertyName: name,
      repositoriesCount: CustomProperties::Public.property_usage(definition)[:repositories_count],
      propertyConsumerUsages: property_usages_payload(definitions_manager.get_condition_usages(name))
    }
  end

  private

  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition], properties_list_enabled: T::Boolean).returns(T::Hash[String, T.untyped]) }
  def definitions_list_payload(definitions, properties_list_enabled:)
    q = properties_list_enabled ? search_query&.downcase || "" : ""
    page = properties_list_enabled ? current_page : 1
    per_page = properties_list_enabled ? DEFINITIONS_PER_PAGE : definitions.size

    definitions.filter! { |d| d.property_name.downcase.include?(q) } if q.present?
    definitions = definitions.paginate(page:, per_page:)

    {
      definitions: definitions_payload(definitions),
      pageCount: definitions.total_pages,
      totalCount: definitions.total_entries,
    }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def list_repos_property_values_payload
    query_result = search_org_repos(
      current_organization,
      current_user,
      search_query,
      current_page,
      sort_order: sort_order,
      user_session:,
      cap_filter:,
    )

    {
      repositories: repos_properties_payload(query_result[:repos]),
      pageCount: query_result[:total_pages],
      repositoryCount: query_result[:total],
    }
  end

  sig { returns(T.nilable(String)) }
  def search_query
    params[:q] if params[:q].is_a?(String)
  end

  sig { returns(T.nilable(String)) }
  def sort_order
    params[:sort] if params[:sort].is_a?(String)
  end

  sig { returns(CustomPropertiesDefinitionsManager) }
  memoize def definitions_manager
    CustomProperties::Public.definitions_manager(current_organization)
  end

  sig { returns(CustomPropertiesValuesManager) }
  memoize def values_manager
    CustomProperties::Public.values_manager(definitions_manager)
  end

  sig { returns(T.nilable(T::Hash[String, String])) }
  def business_info
    return nil unless current_organization.business.present?

    {
      name: current_organization.business.name,
      slug: current_organization.business.slug,
    }
  end

  sig { returns(T::Boolean) }
  def can_manage_business?
    return false unless current_organization.business.present?

    current_organization.business.owner?(current_user)
  end

  sig { void }
  def redirect_to_tab
    permissions = user_permissions

    current_tab = params[:tab]
    current_tab = "properties" if current_tab.blank?

    tabs = if permissions == "all"
      %w[properties set-values]
    elsif permissions == "definitions"
      %w[properties]
    else
      %w[set-values]
    end

    unless tabs.include?(current_tab)
      redirect_to org_custom_properties_path(current_organization, tab: tabs.first)
    end
  end

  sig { returns(String) }
  def user_permissions
    defs_mgr = org_custom_properties_definitions_manager?
    values_editor = org_custom_properties_values_editor?

    if defs_mgr && values_editor
      "all"
    elsif defs_mgr
      "definitions"
    else
      "values"
    end
  end
end
