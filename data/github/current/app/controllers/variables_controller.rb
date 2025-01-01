# typed: true
# frozen_string_literal: true

class VariablesController < AbstractRepositoryController
  include Variables::Helper
  include ActionView::Helpers::NumberHelper
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:edit, :destroy]

  before_action :login_required
  before_action :ensure_admin_access
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
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index]

  def index
    repository_variables = get_initial_repository_variables
    environment_variables = get_initial_environment_variables
    organization_variables = get_initial_organization_variables

    variable_names = variable_names_for_repository(current_repository, current_user, app: variables_app)

    page_info = {
      page_title: Variables::AppsHelper.page_title_for(app_name, current_user),
      selected_link: Variables::AppsHelper.highlight_for(app_name, current_user),
      blank_slate_title:,
      blank_slate_description:,
    }

    usage_metadata = {
      show_environment_variables: show_environment_variables?,
      can_use_org_variables: can_use_org_variables(current_repository.owner),
      repo_can_use_org_variables: repo_can_use_org_variables?,
      is_owner_admin: current_repository.owner.adminable_by?(current_user),
    }

    environment_urls = {}
    environment_variables[:environment_variables].each do |s|
      environment_urls[s[:environment_name]] = edit_repository_environment_path(environment_id: s[:environment_id])
    end

    edit_repo_variables_urls = {}
    delete_repo_variables_urls = {}
    repository_variables[:repository_variables].each do |s|
      edit_repo_variables_urls[s[:name]] = repository_edit_variable_path(app_name: "actions", name: s[:name])
      delete_repo_variables_urls[s[:name]] = repository_delete_variable_path(app_name: "actions", name: s[:name])
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
      is_owner_admin: current_repository.owner.adminable_by?(current_user),
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
    app_name == Variables::AppsHelper::ACTIONS_APP_NAME && current_repository.can_use_environments?
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
end
