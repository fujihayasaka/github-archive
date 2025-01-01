# typed: true
# frozen_string_literal: true

class SecretsController < AbstractRepositoryController
  include Secrets::Helper
  include ActionView::Helpers::NumberHelper
  include ReactHelper

  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:remove_secret, :update]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :sudo_filter, only: [:remove_secret, :update]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:secrets]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:secrets]

  def secrets # rubocop:todo GitHub/UseRestfulActions
    secrets = secrets_for_repository(current_repository, current_user, app: secrets_app, fetch_environments: show_environment_secrets?)
    view = EditRepositories::Pages::SecretsView.new(app_name: app_name, current_repository: current_repository, current_user: current_user)

    environment_urls = {}
    secrets[:environment_secrets].each do |s|
      environment_urls[s[:environment_name]] = edit_repository_environment_path(environment_id: s[:environment_id])
    end

    edit_repo_secret_urls = {}
    delete_repo_secret_urls = {}
    secrets[:repository_secrets].each do |s|
      edit_repo_secret_urls[s[:name]] = repository_edit_secret_path(app_name: view.app_name, secret_name: s[:name])
      delete_repo_secret_urls[s[:name]] = repository_remove_secret_path(app_name: view.app_name, key: s[:name])
    end

    render "edit_repositories/pages/secrets", locals: {
      app: secrets_app,
      public_key: github_public_key(current_repository, key_name: secrets_key_name),
      can_use_org_secrets: can_use_org_secrets?,
      repo_can_use_org_secrets: repo_can_use_org_secrets?,
      secrets:,
      environment_urls:,
      edit_repo_secret_urls:,
      delete_repo_secret_urls:,
      is_owner_admin: current_repository.owner.adminable_by?(current_user),
      view:,
    }
  end

  def can_use_org_secrets? # rubocop:todo GitHub/UseRestfulActions
    current_repository.owner.can_use_org_secrets?
  end

  def repo_can_use_org_secrets? # rubocop:todo GitHub/UseRestfulActions
    return false unless can_use_org_secrets?
    return true if current_repository.public?
    return true if app_name == Secrets::AppsHelper::DEPENDABOT_APP_NAME

    plan_name = current_repository.async_actions_plan_owner.sync.plan_name
    plan_name != ActionsPlanOwner::FREE && plan_name != ActionsPlanOwner::FREE_ORGANIZATION
  end

  def remove_secret # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless secrets_app

    begin
      result = Secrets.delete(
        name: params[:key],
        app: secrets_app,
        owner: current_repository,
        actor: current_user,
      )
    rescue Secrets::Error
    end

    if !result&.success
      flash[:error] = "Failed to delete secret."
    else
      flash[:notice] = "Repository secret deleted."
    end

    redirect_to repository_secrets_path(app_name: app_name)
  end

  def update
    id, encoded = github_public_key(current_repository, key_name: secrets_key_name)

    if params[:encrypted_value].empty? || params[:key_id].to_i != id
      flash[:error] = "Failed to update secret. Please try again."
      return redirect_to repository_secrets_path(app_name: app_name)
    end

    validation = Credz.validate_secret(params[:secret_name], params[:encrypted_value])
    unless validation.succeeded?
      flash[:error] = validation.error
      redirect_to repository_secrets_path(app_name: app_name)
      return
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
        owner: current_repository,
        actor: current_user,
        value: encoded_value,
      )

    rescue Secrets::Error => e
      flash[:error] = "Failed to update secret."
      return redirect_to repository_update_secret_path(secret_name: params[:secret_name], app_name: app_name)
    else
      flash[:notice] = "Secret updated."
    end

    redirect_to repository_secrets_path(app_name: app_name)
  end

  def edit
    return render_404 unless secrets_app

    result = Secrets.fetch(
      name: params[:secret_name],
      app: secrets_app,
      owner: current_repository,
      actor: current_user,
    )

    secret = result&.credential
    return render_404 unless secret

    render "edit_repositories/pages/secrets/edit", locals: {
      public_key: github_public_key(current_repository, key_name: secrets_key_name),
      secret: secret,
      view: EditRepositories::Pages::SecretsView.new(app_name: app_name, current_repository: current_repository, current_user: current_user),
    }
  end

  def new_secret # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless secrets_app

    render "edit_repositories/pages/secrets/new_secret", locals: {
      public_key: github_public_key(current_repository, key_name: secrets_key_name),
      view: EditRepositories::Pages::SecretsView.new(app_name: app_name, current_repository: current_repository, current_user: current_user),
    }
  end

  def add_secret # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless secrets_app

    id, encoded = github_public_key(current_repository, key_name: secrets_key_name)

    if params[:encrypted_value].empty? || params[:key_id].to_i != id
      flash[:error] = "Failed to add secret. Please try again."
      return redirect_to repository_secrets_path(app_name: app_name)
    end

    validation = Credz.validate_secret(params[:secret_name], params[:encrypted_value])
    unless validation.succeeded?
      flash[:error] = validation.error
      return redirect_to repository_secrets_path(app_name: app_name)
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
        owner: current_repository,
        actor: current_user,
        value: encoded_value,
      )
    rescue Secrets::Error => e
      if e.status == 400
        flash[:error] = "Failed to add secret, you've reached the #{number_with_delimiter(Credz::SECRET_REPO_MAX)} secret limit."
      elsif e.status == 409
        flash[:error] = "Failed to add secret, a secret with the same name (#{params[:secret_name].upcase}) already exists."
        return redirect_to repository_add_secret_path(app_name: app_name)
      elsif e.status >= 500
        flash[:error] = "Failed to add secret."
        return redirect_to repository_add_secret_path(app_name: app_name)
      end
    else
      flash[:notice] = "Repository secret added."
    end

    redirect_to repository_secrets_path(app_name: app_name)
  end

  private

  def show_environment_secrets?
    app_name == Secrets::AppsHelper::ACTIONS_APP_NAME && current_repository.can_use_environments?
  end

  def secrets_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_secrets_app ||= Secrets::AppsHelper.app_for(app_name, current_user)
  end

  def secrets_key_name # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_secrets_key_name ||= Secrets::AppsHelper.key_name_for(app_name, current_user)
  end
end
