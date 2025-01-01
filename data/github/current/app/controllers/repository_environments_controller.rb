# typed: false
# frozen_string_literal: true

class RepositoryEnvironmentsController < AbstractRepositoryController
  include Secrets::Helper
  include ActionView::Helpers::NumberHelper
  include Variables::Helper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:remove_secret, :remove_variable, :update_variable, :update_secret, :add_secret, :add_variable]

  before_action :login_required
  before_action :ensure_actions_environments_access
  before_action :ensure_can_use_environments
  before_action :sudo_filter, only: [:remove_secret, :update_secret, :update_variable, :remove_variable, :destroy]

  javascript_bundle :"environment-settings"
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Permissions,
    ApplicationRecord::Iam,
    ApplicationRecord::ActionsEnvironments,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::ActionsEnvironments,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:suggested_approvers]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :edit, :new]

  PAGE_SIZE = 100

  def index
    log_access_metrics
    environments = current_repository.environments.includes(:gates).order(id: :desc)
    environments = environments.paginate(page: current_page, per_page: PAGE_SIZE)
    secret_counts = secret_count_for_environments(current_repository, app: secrets_app, environments: environments)
      .map { |sc| [sc.owner_global_id, sc.count] }.to_h
    variable_counts = variable_count_for_environments(current_repository, app: variables_app, environments: environments)
      .map { |vc| [vc.owner_global_id, vc.count] }.to_h
    render "edit_repositories/pages/environments/index", locals: { environments: environments, secret_counts: secret_counts, variable_counts: variable_counts }
  end

  def new
    environment = current_repository.environments.new
    render "edit_repositories/pages/environments/new", locals: { environment: environment }
  end

  def create
    errors = []
    environment = nil

    Environment.transaction do
      environment = current_repository.environments.new(environment_params)

      if !environment.save
        errors << "There was an error saving your new environment."
        raise ActiveRecord::Rollback
      end
    end

    if errors.any?
      flash[:error] = errors.first
      render "edit_repositories/pages/environments/new", status: :unprocessable_entity, locals: { environment: environment }
    else
      flash[:notice] = "Environment \"#{environment.name}\" created."
      redirect_to edit_repository_environment_path(environment_id: environment.id)
    end
  end

  def edit
    environment = current_repository.environments.includes(gates: [:gate_approvers]).find(params[:environment_id])

    secrets = secrets_for_environment(environment)
    variables = variables_for_environment(environment)

    secrets_vars = map_secrets_and_varibles(secrets, variables, environment)

    render "edit_repositories/pages/environments/edit", locals: {
      environment: environment,
      secrets: secrets,
      edit_secret_urls: secrets_vars[:edit_secret_urls],
      delete_secret_urls: secrets_vars[:delete_secret_urls],
      edit_variable_urls:  secrets_vars[:edit_variable_urls],
      delete_variable_urls:  secrets_vars[:delete_variable_urls],
      public_key: github_public_key(environment, key_name: Platform::EncryptionKeys::CUSTOM_TASKS),
      variables: variables,
      show_branch_policies: can_edit_repo_protections?,
    }
  end

  def update
    environment = current_repository.environments.find(params[:environment_id])
    return render_404 unless environment

    errors = []

    environment.transaction do
      if use_approval_gate
        has_invisible_users = environment.calculate_reviewers_invisible_to_user(current_user) > 0
        if !params[:reviewers].present? && !has_invisible_users
          errors << "No valid reviewers found."
          raise ActiveRecord::Rollback
        end

        reviewers_array = get_reviewers_array
        if environment.has_approval_gate?
          environment.approval_gate.gate_approvers.each do |gate_approver|
            approver = gate_approver.approver
            if approver.is_a?(Team) && !approver.visible_to?(current_user)
              reviewers_array = reviewers_array.push(approver)
            end
          end
        end
        environment.create_or_update_approval_gate(reviewers_array, prevent_self_review: require_different_reviewer)
        if environment.errors.present?
          errors << environment.errors.full_messages.first
          raise ActiveRecord::Rollback
        end
      else
        environment.remove_approval_gate
      end

      if use_wait_gate
        environment.create_or_update_wait_gate(wait_time)
        if environment.errors.present?
          errors << environment.errors.full_messages.first
          raise ActiveRecord::Rollback
        end
      else
        environment.remove_wait_gate
      end

      environment.create_or_update_custom_protection_rules(custom_protection_rule_integrations)

      environment.gates_admin_enforced = !params[:"gates-admin-bypass-allowed"].present?

      if !environment.save
        errors << "Could not update environment."
        raise ActiveRecord::Rollback
      end
    end

    if errors.any?
      flash[:error] = errors.first

      environment = current_repository.environments.includes(gates: [:gate_approvers]).find(params[:environment_id])

      secrets = secrets_for_environment(environment)
      variables = variables_for_environment(environment)
      secrets_vars = map_secrets_and_varibles(secrets, variables, environment)

      render "edit_repositories/pages/environments/edit", status: :unprocessable_entity, locals: {
        environment: environment,
        secrets: secrets,
        public_key: github_public_key(environment, key_name: Platform::EncryptionKeys::CUSTOM_TASKS),
        variables: variables,
        edit_secret_urls: secrets_vars[:edit_secret_urls],
        delete_secret_urls: secrets_vars[:delete_secret_urls],
        edit_variable_urls:  secrets_vars[:edit_variable_urls],
        delete_variable_urls:  secrets_vars[:delete_variable_urls],
        show_branch_policies: can_edit_repo_protections?,
      }
    else
      flash[:notice] = "Environment \"#{environment.name}\" updated."
      redirect_to edit_repository_environment_path(environment_id: environment.id)
    end
  end

  def destroy
    environment = current_repository.environments.find(params[:environment_id])
    environment.destroy!
    flash[:notice] = "Environment deleted."
    redirect_to repository_environments_path
  end

  def suggested_approvers # rubocop:todo GitHub/UseRestfulActions
    query = AutocompleteQuery.new(
      current_user,
      params[:q],
      organization: current_repository.organization,
      include_teams: true
    )

    suggestions = filter_read_actors(query.suggestions)

    respond_to do |format|
      format.html_fragment do
        render partial: "edit_repositories/pages/environments/approver_suggestions", formats: :html, locals: { suggestions: suggestions }
      end

      format.html do
        render partial: "edit_repositories/pages/environments/approver_suggestions", locals: { suggestions: suggestions }
      end
    end
  end

  def add_secret # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    id, encoded = github_public_key(environment, key_name: Platform::EncryptionKeys::CUSTOM_TASKS)

    if params[:encrypted_value].empty? || params[:key_id].to_i != id
      return send_json_response("Failed to add secret. Please try again.", 400)
    end

    validation = Credz.validate_secret(params[:secret_name], params[:encrypted_value])
    unless validation.succeeded?
      return send_json_response("Failed to add secret: #{validation.error}", 400)
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_secret(params[:encrypted_value])
    else
      Secrets.embed(id, Base64.strict_decode64(params[:encrypted_value]))
    end

    encoded_value = Base64.strict_encode64(value)

    begin
      Secrets.create(
        name: params[:secret_name],
        app: secrets_app,
        owner: environment,
        actor: current_user,
        value: encoded_value,
      )
    rescue Secrets::Error => e
      if e.status == 400
        return send_json_response("Failed to add secret: you've reached the #{number_with_delimiter(Credz::SECRET_ENV_MAX)} secret limit.", e.status)
      elsif e.status == 409
        return send_json_response("Failed to add secret: a secret with the same name already exists (#{params[:secret_name].upcase}).", e.status)
      else
        return send_json_response("Failed to add secret.", e.status)
      end
    else
      return send_json_response("Environment secret added.", 201)
    end

    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  def update_secret # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    id, encoded = github_public_key(environment, key_name: Platform::EncryptionKeys::CUSTOM_TASKS)

    if params[:encrypted_value].empty? || params[:key_id].to_i != id
      return send_json_response("Failed to update secret. Please try again.", 400)
    end

    validation = Credz.validate_secret(params[:secret_name], params[:encrypted_value])
    unless validation.succeeded?
      return send_json_response("Failed to update secret: #{validation.error}", 400)
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_secret(params[:encrypted_value])
    else
      Secrets.embed(id, Base64.strict_decode64(params[:encrypted_value]))
    end

    encoded_value = Base64.strict_encode64(value)

    begin
      Secrets.update(
        name: params[:secret_name],
        app: secrets_app,
        owner: environment,
        actor: current_user,
        value: encoded_value,
      )
    rescue Secrets::Error
      return send_json_response("Failed to update secret.", 400)
    else
      return send_json_response("Environment secret updated.", 204)
    end

    redirect_to edit_repository_environment_path(environment_id: environment.id)
  end

  def remove_secret # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    begin
      result = Secrets.delete(
        app:  secrets_app,
        owner: environment,
        actor: current_user,
        name:  params[:secret_name]
      )
    rescue Secrets::Error
    end

    if !result&.success
      send_json_response("Failed to delete secret.", 400)
    else
      send_json_response("Secret deleted.", 204)
    end
  end

  def add_variable # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    validation = Varz.validate_new_variable(params[:variable_name], params[:variable_value])
    unless validation.succeeded?
      return send_json_response("Failed to add variable: #{validation.error}", 422)
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    begin
      Variables.store(
        name: params[:variable_name],
        app: variables_app,
        owner: environment,
        actor: current_user,
        value: encoded_value,
      )
    rescue Variables::Error => e
      # In multi-tenant mode, renderer intercepts 429 and treats it universally as a rate limit,
      # so we need to do what the old experience does and use a different render status - the json
      # status should stay the same though.
      if e.status == 429
        send_json_response("Failed to add variable: You've reached the #{number_with_delimiter(Varz::VARIABLE_ENV_MAX)} variable limit.", e.status, 400)
      elsif e.status == 409
        send_json_response("Failed to add variable: An environment variable with this name already exists.", e.status, 400)
      else
        send_json_response("Failed to add variable. Please try again.", e.status, 400)
      end
    else
      send_json_response("Environment variable added.", 201)
    end
  end

  def update_variable # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    validation = Varz.validate_variable(params[:variable_updated_name], params[:variable_value])
    unless validation.succeeded?
      return send_json_response("Failed to update variable: #{validation.error}", 422)
    end

    encoded_value = Base64.strict_encode64(params[:variable_value])

    begin
      Variables.update(
        name: params[:variable_name],
        app: variables_app,
        owner: environment,
        actor: current_user,
        value: encoded_value,
        updated_name: params[:variable_updated_name],
      )
    rescue Variables::Error => e
      if e.status == 409
        send_json_response("Failed to update variable: An environment variable with this name already exists.")
      else
        send_json_response("Failed to update variable. Please try again.")
      end
    else
      send_json_response("Environment variable updated.", 204)
    end
  end

  def remove_variable # rubocop:todo GitHub/UseRestfulActions
    environment = current_repository.environments.find(params[:environment_id])

    begin
      result = Variables.delete(
        app:  variables_app,
        owner: environment,
        actor: current_user,
        name:  params[:variable_name]
      )
    rescue Variables::Error
    end

    if !result&.success
      send_json_response("Failed to delete variable.", 400)
    else
      send_json_response("Variable deleted.", 204)
    end
  end

  private

  def secrets_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_secrets_app ||= Secrets::AppsHelper.app_for(Secrets::AppsHelper::ACTIONS_APP_NAME, current_user)
  end

  def secrets_for_environment(environment)
    secrets_for(environment, app: secrets_app).map do |secret| {
        name: secret.name,
        updated_at: Secrets.secret_updated_at(secret)
      }
    end
  end

  def variables_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_variables_app ||= Variables::AppsHelper.app_for(Variables::AppsHelper::ACTIONS_APP_NAME, current_user)
  end

  def variables_for_environment(environment)
    variables_for(environment, app: variables_app).map do |variable| {
        name: variable.name,
        value: variable.value,
        updated_at: Variables.variable_updated_at(variable)
      }
    end
  end

  def filter_read_actors(actors)
    actors.select do |actor|
      # Make sure actor is a team and also is not a "secret" team
      if actor.is_a?(Team)
        !actor.secret? && (actor.id_and_ancestor_ids & team_ids_with_read_access).any?
      else
        user_ids_with_read_access.include? actor.id
      end
    end
  end

  def team_ids_with_read_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @team_ids_with_read_access ||= current_repository.actor_ids(type: Team)
  end

  def user_ids_with_read_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @user_ids_with_read_access ||= current_repository.user_ids_with_privileged_access(min_action: :read)
  end

  def environment_params
    params.require(:environment).permit(:name)
  end

  def use_wait_gate
    params[:"use-wait-gate"].present?
  end

  def wait_time
    p = params.require(:wait_gate).permit(:timeout)
    p[:timeout]
  end

  def use_approval_gate
    params[:"use-approval-gate"].present?
  end

  def require_different_reviewer
    !!params["require-different-reviewer"]
  end

  def get_reviewers_array
    if params[:reviewers].present?
      return params[:reviewers].map do |reviewer_global_id|
        typed_object_from_id(
          [Platform::Objects::User, Platform::Objects::Team],
          reviewer_global_id,
        )
      rescue Platform::Errors::NotFound
        # Ignore if the entity cannot be found
      end.compact
    end
    []
  end

  def custom_protection_rule_integrations
    (params[:custom_protection_rule_integrations] || []).map(&:to_i)
  end

  def ensure_can_use_environments
    render_404 unless current_repository.can_use_environments?
  end

  def map_secrets_and_varibles(secrets, variables, environment)
    result = {}
    edit_secret_urls = {}
    delete_secret_urls = {}
    secrets.each do |s|
      edit_secret_urls[s[:name]] = repository_environment_update_secret_path(
        user_id: current_repository.owner.display_login,
        repository: current_repository,
        environment_id: environment.id,
        secret_name: s[:name]
      )
      delete_secret_urls[s[:name]] = repository_environment_remove_secret_path(
        user_id: current_repository.owner.display_login,
        repository: current_repository,
        environment_id: environment.id,
        secret_name: s[:name]
      )
    end

    edit_variable_urls = {}
    delete_variable_urls = {}
    variables.each do |v|
      edit_variable_urls[v[:name]] = repository_environment_update_variable_path(
        user_id: current_repository.owner.display_login,
        repository: current_repository,
        environment_id: environment.id,
        variable_name: v[:name]
      )
      delete_variable_urls[v[:name]] = repository_environment_remove_variable_path(
        user_id: current_repository.owner.display_login,
        repository: current_repository,
        environment_id: environment.id,
        variable_name: v[:name]
      )
    end

    {
      edit_secret_urls: edit_secret_urls,
      delete_secret_urls: delete_secret_urls,
      edit_variable_urls: edit_variable_urls,
      delete_variable_urls: delete_variable_urls
    }
  end

  def send_json_response(message, response_code, outer_status = nil)
    respond_to do |format|
      format.json do
        return render json: {
          message: message,
          status: response_code
        }, status: outer_status.nil? ? response_code : outer_status
      end
    end
  end

  def can_edit_repo_protections?
    current_repository.async_can_edit_repo_protections?(current_user).sync
  end

  # Tracking how many users are accessing environments as non admins
  def log_access_metrics
    if current_repository.adminable_by?(current_user)
      GitHub.dogstats.increment("actions.repo.settings.repository_environments_controller", tags: ["admin:true"])
    else
      GitHub.dogstats.increment("actions.repo.settings.repository_environments_controller", tags: ["admin:false"])
    end
  end
end
