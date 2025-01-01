# typed: strict
# frozen_string_literal: true

class Orgs::CustomPropertiesSettingsController < Orgs::Controller
  include Orgs::CustomPropertiesHelper
  include Orgs::RepoListPayloadHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include CustomPropertiesCore::Errors

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

  sig { void }
  def index
    add_client_feature_flag([:repos_list_show_filter_dialog, :custom_properties_shared_components])
    add_client_feature_flag([:custom_properties_url_type], entity: current_organization) do |_, entity|
      Repositories.domain.custom_properties.url_type_enabled?(entity)
    end

    definitions_count = Repositories.domain.custom_properties.get_own_definitions(current_organization).size

    base_payload = {
      permissions: user_permissions,
      ownDefinitionsCount: definitions_count,
    }

    page_payload = if params[:tab] == "set-values"
      definitions = Repositories.domain.custom_properties.get_definitions(current_organization)

      {
        activeTab: "set-values",
        **base_payload,
        **list_repos_property_values_payload,
        definitions: definitions_payload(definitions),
      }
    else
      results = Repositories.domain.custom_properties.search_definitions(current_organization, search_query, current_page)

      list_payload = definitions_list_payload(**results)

      {
        activeTab: "properties",
        **base_payload,
        **list_payload,
      }
    end

    render_react_app(
      payload: page_payload,
      title: "Settings · Custom properties · #{current_organization.name}",
      page_data: { selected_link: :custom_properties_for_repos },
    )
  end

  sig { void }
  def show
    add_client_feature_flag([:custom_properties_shared_components])
    add_client_feature_flag([:custom_properties_url_type], entity: current_organization) do |_, entity|
      Repositories.domain.custom_properties.url_type_enabled?(entity)
    end

    name = params[:property_name]

    definitions = Repositories.domain.custom_properties.get_definitions(current_organization)

    definition = name ? Repositories.domain.custom_properties.get_definition(current_organization, name) : nil

    return redirect_to org_custom_properties_path(current_organization) if definition.nil? && name.present?

    title = "Settings · Custom properties · #{current_organization.name} · #{definition ? "#{definition.property_name}" : "Create custom property"}"

    render_react_app(
      payload: {
        definition: definition ? definition_payload(definition) : nil,
        business: business_info,
        propertyNames: definitions.map { |d| d.property_name },
        canManageProperty: can_manage_business?,
      },
      title: title,
      page_data: { selected_link: :custom_properties_for_repos },
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
        current_organization,
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
    Repositories.domain.custom_properties.delete_definition(current_organization, params[:property_name])
    head 200
  end

  sig { void }
  def update_repos_properties # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_organization

    # Cleanup with custom_properties_shared_components -> drop `repoIds`
    payload = params.slice(:repoIds, :targetIds, :properties).permit!

    repo_ids = T.cast(payload[:repoIds] || payload[:targetIds], T::Array[Integer])
    properties = T.cast(payload[:properties].to_h, T::Hash[String, String])

    repos = current_organization.repositories.where(id: repo_ids).to_a
    return head :not_found if repo_ids - repos.pluck(:id) != []

    definitions = Repositories.domain.custom_properties.get_definitions(current_organization)

    property_names = properties.keys
    return head :not_found if property_names - definitions.pluck(:property_name) != []

    GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.batch_size", repos.size)
    GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.property_names_size", properties.size)

    begin
      GitHub.dogstats.distribution_time("custom_properties_settings.update_repos_properties.time") do
        Repositories.domain.custom_properties.set_properties_for(current_organization, repos, properties, actor: current_user)
      end

      head :ok
    rescue CustomPropertiesCore::Errors::EditPropertyPermissionError => error
      render json: { error: error.full_message }, status: 403
    rescue CustomPropertiesCore::Errors::PropertyValidationError => error
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

    definition = Repositories.domain.custom_properties.get_definition(current_organization, name)

    return render_404 unless definition

    count = Repositories.domain.custom_properties.property_usage_count(definition)

    # Remove repositoriesCount with custom_properties_shared_components FF
    render json: {
      propertyName: name,
      repositoriesCount: count,
      count: count
    }
  end

  private

  sig do
    params(
      items: T::Array[CustomProperties::IPropertyDefinition],
      total_pages: Integer,
      total_entries: T.nilable(Integer)
    ).returns(T::Hash[String, T.untyped])
  end
  def definitions_list_payload(items:, total_pages: 1, total_entries: nil)
    {
      definitions: definitions_payload(items),
      pageCount: total_pages,
      totalCount: total_entries || items.size,
    }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def list_repos_property_values_payload
    query_result = Search::Repositories.search_repos(
      current_user,
      search_query,
      current_page,
      scope: { org: current_organization },
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
