# typed: true
# frozen_string_literal: true

class VariablesController < AbstractRepositoryController
  include Variables::Helper
  include ActionView::Helpers::NumberHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:edit, :destroy]

  before_action :login_required
  before_action :ensure_has_fgp_or_admin
  before_action :ensure_variables_enabled
  before_action :sudo_filter, only: [:destroy, :update]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::ActionsEnvironments,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Authnd,
    only: [:edit]

  def index
    log_access_metrics
    simplified = current_repository.feature_flag_enabled?(:actions_simplified_secrets_vars_pages, default: false)

    repository_variables = get_initial_repository_variables
    organization_variables = get_initial_organization_variables

    # When the simplified view is enabled, environment variables and environment URLs
    # are not displayed, so skip loading them to avoid unnecessary service calls.
    if simplified
      environment_variables = { environment_variables: [], total_count: 0 }
      environment_urls = {}
    else
      environment_variables = get_initial_environment_variables
      environment_urls = {}
      environment_variables[:environment_variables].each do |s|
        environment_urls[s[:environment_name]] = edit_repository_environment_path(environment_id: s[:environment_id])
      end
    end

    page_info = {
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
      blank_slate_title:,
      blank_slate_description:,
    }

    usage_metadata = {
      show_environment_variables: show_environment_variables?,
      show_org_variables: show_org_variables?,
      repo_can_use_org_variables: repo_can_use_org_variables?,
      can_manage_org_variables: can_manage_org_variables?,
    }

    edit_repo_variables_urls = {}
    delete_repo_variables_urls = {}
    repository_variables[:repository_variables].each do |s|
      edit_repo_variables_urls[s[:name]] = repository_edit_variable_path(app_name: app_name, name: s[:name])
      delete_repo_variables_urls[s[:name]] = repository_delete_variable_path(app_name: app_name, name: s[:name])
    end

    if app_name == Variables::AppsHelper::AGENTS_APP_NAME && FeatureFlag.vexi.enabled?(:agents_secrets_fgp_custom_role, current_repository.owner, default: false)
      can_write_repo_agent_secrets = current_repository.can_write_repository_agent_secrets?(current_user)
      can_write_repo_agent_variables = current_repository.can_write_repository_agent_variables?(current_user)
    else
      can_write_repo_agent_secrets = false
      can_write_repo_agent_variables = false
    end

    render "edit_repositories/pages/variables", locals: {
      app: variables_app,
      app_name:,
      page_info:,
      repository_variables:,
      environment_variables:,
      organization_variables:,
      environment_urls:,
      edit_repo_variables_urls:,
      delete_repo_variables_urls:,
      usage_metadata:,
      can_write_repo_variables: current_repository.can_write_repository_actions_variables?(current_user),
      can_write_repo_secrets: current_repository.can_write_repository_actions_secrets?(current_user),
      can_write_repo_agent_secrets:,
      can_write_repo_agent_variables:,
    }
  end

  def new
    variable_name = params[:variable_name].present? ? params[:variable_name] : ""

    render "edit_repositories/pages/variables/new_variable", locals: {
      app_name: app_name,
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
      variable_name: variable_name,
    }
  end

  def create
    validation = Varz.validate_new_variable(params[:variable_name], params[:variable_value])
    unless validation.succeeded?
      return render json: { error: validation.error, status: 422 }, status: :bad_request
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    begin
      Variables.store(
        name: params[:variable_name],
        app: variables_app,
        owner: current_repository,
        actor: current_user,
        value: encoded_value,
      )
    rescue Variables::Error => e
      error_message = "Failed to add variable. Please try again."

      if e.status == 429
        error_message = "Failed to add variable, you've reached the #{number_with_delimiter(Varz::VARIABLE_REPO_MAX)} variable limit."
      elsif e.status == 409
        error_message = "A repository variable with this name already exists."
      end

      return render json: { error: error_message, status: e.status  }, status: :bad_request
    end

    redirect_to repository_variables_path(app_name: app_name)
  end

  def destroy
    begin
      result = Variables.delete(
        name: params[:name],
        app: variables_app,
        owner: current_repository,
        actor: current_user,
      )
    rescue Variables::Error
    end

    if result&.success
      flash[:notice] = "Repository variable deleted."
    else
      flash[:error] = "Failed to delete variable."
    end

    redirect_to repository_variables_path(app_name: app_name)
  end

  def edit
    result = Variables.fetch(
      name: params[:name],
      app: variables_app,
      owner: current_repository,
      actor: current_user,
    )

    variable = result&.variable
    return render_404 unless variable

    render "edit_repositories/pages/variables/edit_variable", locals: {
      app_name: app_name,
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
      variable: variable,
    }
  end

  def update
    validation = Varz.validate_variable(params[:variable_updated_name], params[:variable_value])
    unless validation.succeeded?
      return render json: { error: validation.error, status: 422 }, status: :bad_request
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    begin
      Variables.update(
        name: params[:name],
        app: variables_app,
        owner: current_repository,
        actor: current_user,
        value: encoded_value,
        updated_name: params[:variable_updated_name],
      )
    rescue Variables::Error => e
      error_message = "Failed to update variable. Please try again."

      if e.status == 409
        error_message = "A repository variable with this name already exists."
      end

      return render json: { error: error_message, status: e.status  }, status: :bad_request
    end

    redirect_to repository_variables_path(app_name: app_name)
  end

  private

  def show_environment_variables?
    repo_has_env_access = app_name == Variables::AppsHelper::ACTIONS_APP_NAME && current_repository.can_use_environments?
    user_has_permissions = current_repository.adminable_by?(current_user) || current_repository.can_write_repository_actions_environments?(current_user)
    repo_has_env_access && user_has_permissions
  end

  def show_org_variables?
    repo_has_org_access = can_use_org_variables(current_repository.owner)
    if FeatureFlag.vexi.enabled?("actions_secrets_variables_user_owned_repo_fix", current_repository, default: false)
      # New behavior: Guard organization-specific methods to prevent NoMethodError on User-owned repos
      user_has_permissions = current_repository.adminable_by?(current_user) || (current_repository.owner.organization? && current_repository.owner.can_write_organization_actions_variables?(current_user))
    else
      # Old behavior: May raise NoMethodError on User-owned repos
      user_has_permissions = current_repository.adminable_by?(current_user) || current_repository.owner.can_write_organization_actions_variables?(current_user)
    end
    repo_has_org_access && user_has_permissions
  end

  def can_manage_org_variables?
    if FeatureFlag.vexi.enabled?("actions_secrets_variables_user_owned_repo_fix", current_repository, default: false)
      # New behavior: Guard organization-specific methods to prevent NoMethodError on User-owned repos
      current_repository.owner.adminable_by?(current_user) || (current_repository.owner.organization? && current_repository.owner.can_write_organization_actions_variables?(current_user))
    else
      # Old behavior: May raise NoMethodError on User-owned repos
      current_repository.owner.adminable_by?(current_user) || current_repository.owner.can_write_organization_actions_variables?(current_user)
    end
  end

  def get_initial_environment_variables
    return { environment_variables: [], total_count: 0 } unless show_environment_variables?

    # Variables are no longer rendered paginated; to avoid drastic refactors we just fetch page 1 with 1000 items
    response = env_variables_for_repository(current_repository, current_user, app: variables_app, page: 1)

    {
      environment_variables: response[:environment_variables],
      total_count: response[:total_count],
    }
  end

  def get_initial_organization_variables
    return { organization_variables: [], total_count: 0 } unless can_use_org_variables(current_repository.owner)

    # Variables are no longer rendered paginated; to avoid signficant refactors we just fetch page 1 with 1000 items
    response = org_variables_for_repository(current_repository, current_user, app: variables_app, page: 1)

    {
      organization_variables: response[:organization_variables],
      total_count: response[:total_count],
    }
  end

  def get_initial_repository_variables
    # Variables are no longer rendered paginated; to avoid signficant refactors we just fetch page 1 with 1000 items
    response = paginated_variables_for(current_repository, app: variables_app, page: 1)

    variables = response[:variables].map do |variable| {
      name: variable.name,
      updated_at: Variables.variable_updated_at(variable),
      value: variable.value,
    }
    end

    {
      repository_variables: variables,
      total_count: response[:total_count],
    }
  end

  def variables_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_variables_app ||= Variables::AppsHelper.app_for(app_name, current_user)
  end

  def ensure_variables_enabled
    render_404 unless variables_app
  end

  def ensure_has_fgp_or_admin
    return if current_repository.adminable_by?(current_user)
    if app_name == Variables::AppsHelper::AGENTS_APP_NAME
      if FeatureFlag.vexi.enabled?(:agents_secrets_fgp_custom_role, current_repository.owner, default: false) &&
          current_repository.can_write_repository_agent_variables?(current_user)
        return
      end
    else
      return if current_repository.can_write_repository_actions_variables?(current_user)
    end
    render_404
  end

  # Tracking how many users are accessing variables as non admins
  def log_access_metrics
    is_admin = current_repository.adminable_by?(current_user)
    GitHub.dogstats.increment("actions.repo.settings.variables_controller", tags: ["admin:#{is_admin}"])

    if app_name == Variables::AppsHelper::AGENTS_APP_NAME
      GitHub.dogstats.increment("agents.repo.settings.variables_controller", tags: ["admin:#{is_admin}"])
    end
  end
end
