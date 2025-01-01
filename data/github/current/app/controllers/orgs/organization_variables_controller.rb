# typed: true
# frozen_string_literal: true

class Orgs::OrganizationVariablesController < Orgs::Controller
  include Variables::Helper
  include ActionView::Helpers::NumberHelper
  include ApplicationController::VerifiedFetchDependency
  include Organization::PermissionsDependency

  allow_verified_fetch only: [:edit, :destroy]

  before_action :login_required
  before_action :organization_admin_or_actions_variables_fine_grained_permission
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_variables_enabled
  before_action :ensure_can_use_org_variables, except: :index
  before_action :sudo_filter, only: [:destroy, :update]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :list_partial, :new, :edit]

  VISIBILITIES = {
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_ALL_REPOS => {
      label: "All repositories",
      description: "This variable may be used by any repository in the organization.",
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_PRIVATE_REPOS => {
      label: "Private repositories",
      description: "This variable may be used by any private repository in the organization.",
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This variable may only be used by specifically selected repositories.",
    }
  }.freeze

  ENTERPRISE_VISIBILITIES = {
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_ALL_REPOS => {
      label: "All repositories",
      description: "This variable may be used by any repository in the organization.",
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_PRIVATE_REPOS => {
      label: "Private and internal repositories",
      description: "This variable may be used by any private or internal repository in the organization.",
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This variable may only be used by specifically selected repositories.",
    }
  }.freeze

  FREE_PLAN_VISIBILITIES = {
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_ALL_REPOS => {
      label: "Public repositories",
      description: "This variable may be used by public repositories in the organization.
      Paid GitHub plans include private repositories.",
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_PRIVATE_REPOS => {
      label: "Private repositories",
      description: "Organization variables cannot be used by private repositories with your plan.",
      disabled: true
    },
    GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This variable may only be used by specifically selected repositories.",
    }
  }.freeze

  def index
    response = paginated_variables_for(current_organization, app: variables_app, page: 1)

    variables = response[:variables].map do |variable| {
        name: variable.name,
        visibility_description: visibility_description_for_variable(variable, can_use_variables_for_private_repos?, current_organization.business.present?),
        updated_at: Variables.variable_updated_at(variable),
        value: Base64.strict_decode64(variable.value),
      }
    end

    edit_org_var_urls = {}
    delete_org_var_urls = {}
    variables.each do |v|
      edit_org_var_urls[v[:name]] = organization_edit_variable_path(app_name:, name: v[:name])
      delete_org_var_urls[v[:name]] = organization_delete_variable_path(app_name:, name: v[:name])
    end

    if response[:total_count] > variables_per_page
      next_page_url = organization_variables_list_partial_path(page: 2)
    else
      next_page_url = nil
    end

    page_info = {
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
      next_page_url: next_page_url,
    }

    render "settings/organization/variables/index", locals: {
      can_use_org_variables: can_use_org_variables?,
      can_use_variables_for_private_repos: can_use_variables_for_private_repos?,
      variables: variables,
      edit_org_var_urls:,
      delete_org_var_urls:,
      total_count: response[:total_count],
      page_info: page_info,
      variables_per_page: variables_per_page,
      can_write_organization_actions_variables: current_organization.can_write_organization_actions_variables?(current_user),
      can_write_organization_actions_secrets: current_organization.can_write_organization_actions_secrets?(current_user)
    }
  end

  def list_partial # rubocop:todo GitHub/UseRestfulActions
    current_page = params[:page].to_i
    current_page = 1 if current_page == 0

    response = paginated_variables_for(current_organization, app: variables_app, page: current_page)

    variables = response[:variables].map do |variable| {
        name: variable.name,
        visibility_description: visibility_description_for_variable(variable, can_use_variables_for_private_repos?, current_organization.business.present?),
        updated_at: Variables.variable_updated_at(variable),
        value: Base64.strict_decode64(variable.value),
      }
    end

    if response[:total_count] > variables_per_page * current_page
      next_page_url = organization_variables_list_partial_path(page: current_page + 1)
    else
      next_page_url = nil
    end

    render partial: "settings/organization/variables/variables_list", locals: {
      variables: variables,
      next_page_url: next_page_url,
    }
  end

  def new
    name = params[:name].present? ? params[:name] : ""

    if can_use_variables_for_private_repos?
      default_visibility = GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_PRIVATE_REPOS
    else
      default_visibility = GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_ALL_REPOS
    end

    page_info = {
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
    }

    repositories = current_organization.repositories
    unless current_organization.plan.supports?(:private_secrets_and_variables)
      repositories = repositories.public_scope
    end

    render "settings/organization/variables/new_variable", locals: {
      total_count: repositories.count,
      visibilities: visibilities,
      default_visibility: default_visibility,
      can_use_variables_for_private_repos: can_use_variables_for_private_repos?,
      page_info: page_info,
      name: name,
      app_name: app_name,
    }
  end

  def create
    validation = Varz.validate_new_org_variable(params[:name], params[:variable_value], params[:visibility].to_sym)
    unless validation.succeeded?
      return render json: { error: validation.error, status: 422 }, status: :bad_request
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    visibility = params[:visibility]
    repository_node_ids = visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS.to_s ? Array(params[:repository_ids]) : []
    repository_ids = repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids).order(:id).map(&:global_relay_id)

    begin
      Variables.store(
        name: params[:name],
        app: variables_app,
        owner: current_organization,
        actor: current_user,
        value: encoded_value,
        visibility: visibility.to_sym,
        selected_repositories: selected_repositories,
      )
    rescue Variables::Error => e
      error_message = "Failed to add variable. Please try again."

      if e.status == 429
        error_message = "Failed to add variable, you've reached the #{number_with_delimiter(Varz::VARIABLE_ORG_MAX)} variable limit."
      elsif e.status == 409
        error_message = "An organization variable with this name already exists."
      end

      return render json: { error: error_message, status: e.status  }, status: :bad_request
    end

    redirect_to organization_variables_path
  end

  def destroy_variable_partial # rubocop:todo GitHub/UseRestfulActions
    render_404 unless request.xhr?

    result = Variables.fetch(
      name: params[:name],
      app: variables_app,
      owner: current_organization,
      actor: current_user,
    )

    variable = result&.variable
    if variable&.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      selected_repositories = variable.selected_repositories.map(&:global_id).to_set
      selected_repository_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
      repositories = current_organization.repositories.where(id: selected_repository_ids)
    end

    render partial: "settings/organization/variables/remove_variable",
           locals: {
              variable_name: params[:name],
              repositories: repositories,
           }
  end

  def destroy
    begin
      result = Variables.delete(
        name: params[:name],
        app: variables_app,
        owner: current_organization,
        actor: current_user,
      )
    rescue Variables::Error
    end

    if result&.success
      flash[:notice] = "Organization variable deleted."
    else
      flash[:error] = "Failed to delete variable."
    end

    redirect_to organization_variables_path
  end

  def edit
    begin
      result = Variables.fetch(
        name: params[:name],
        app: variables_app,
        owner: current_organization,
        actor: current_user,
      )
    rescue Variables::Error
      return render_404
    end

    variable = result&.variable
    return render_404 unless variable

    page_info = {
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
    }

    selected_repository_node_ids = variable.selected_repositories.map(&:global_id).to_set
    repository_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set

    repositories = current_organization.repositories
    unless current_organization.plan.supports?(:private_secrets_and_variables)
      repositories = repositories.public_scope
    end

    render "settings/organization/variables/edit_variable", locals: {
      variable: variable,
      visibilities: visibilities,
      can_use_variables_for_private_repos: can_use_variables_for_private_repos?,
      page_info: page_info,
      repositories: selected_repositories,
      selected_repositories: selected_repository_global_ids,
      total_count: repositories.count - selected_repositories.count,
      selected_visibility: variable.visibility,
      repository_item_prefix: repository_items_aria_id_prefix(variable_name: variable.name)
    }
  end

  def update
    validation = Varz.validate_variable(params[:variable_updated_name], params[:variable_value])
    unless validation.succeeded?
      return render json: { error: validation.error, status: 422 }, status: :bad_request
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    visibility = params[:visibility]
    repository_node_ids = visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS.to_s ? Array(params[:repository_ids]) : []
    repository_ids = repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids).order(:id).map(&:global_relay_id)

    begin
      Variables.update(
        name: params[:name],
        app: variables_app,
        owner: current_organization,
        actor: current_user,
        value: encoded_value,
        visibility: visibility.to_sym,
        selected_repositories: selected_repositories,
        updated_name: params[:variable_updated_name],
      )
    rescue Variables::Error => e
      error_message = "Failed to update variable. Please try again."

      if e.status == 409
        error_message = "An organization variable with this name already exists."
      end

      return render json: { error: error_message, status: e.status  }, status: :bad_request
    end

    redirect_to organization_variables_path
  end

  private

  def ensure_can_use_org_variables
    return render_404 unless can_use_org_variables?
  end

  def can_use_org_variables?
    can_use_org_variables(current_organization)
  end

  def can_use_variables_for_private_repos?
    return true if current_organization.plan.supports?(:private_secrets_and_variables)
  end

  def visibilities
    if can_use_variables_for_private_repos?
      current_organization.business.present? ? ENTERPRISE_VISIBILITIES : VISIBILITIES
    else
      FREE_PLAN_VISIBILITIES
    end
  end

  def variables_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_variables_app ||= Variables::AppsHelper.app_for(app_name, current_user)
  end

  def ensure_variables_enabled
    render_404 unless variables_app
  end
end
