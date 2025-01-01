# typed: true
# frozen_string_literal: true

class Settings::CodespacesController < ApplicationController
  include Secrets::Helper

  before_action :login_required

  # require codespaces feature enabled
  before_action :require_user_codespace_settings_feature, except: [:update_gpg_authorization]

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  helper_method :grouped_options_for_default_location

  def index
    secrets = Codespaces::UserSecret.for(current_user)
    public_key = public_key(current_user)
    user_secrets = secrets.map do |secret|
      {
        name: secret.name,
        visibility_description: visibility_description_for_codespace_user_secret(secret),
        updated_at: secret.updated_at
      }
    end

    edit_secret_urls = {}
    delete_secret_urls = {}
    user_secrets.each do |s|
      edit_secret_urls[s[:name]] = edit_codespaces_user_secret_path(name: s[:name])
      delete_secret_urls[s[:name]] = codespaces_user_secret_path(name: s[:name])
    end

    render "settings/codespaces/index", locals: {
      secrets: user_secrets,
      trusted_repositories: current_user_trusted_repositories,
      default_location_for_user: current_user.codespace_default_location,
      public_key:,
      edit_secret_urls:,
      delete_secret_urls:,
    }
  end

  def update_codespace_dotfiles_enabled # rubocop:todo GitHub/UseRestfulActions
    if params[:codespace_dotfiles_enabled]
      current_user.enable_codespace_dotfiles(actor: current_user)
    else
      current_user.disable_codespace_dotfiles(actor: current_user)
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/dotfiles", locals: { show_check: true }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_codespace_preferred_editor # rubocop:todo GitHub/UseRestfulActions
    user_settings = Codespaces::Settings.for_user(current_user)
    editor_updated = user_settings.update({ preferred_editor: params[:codespace_preferred_editor] })

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/editor", locals: { show_check: editor_updated, show_error: !editor_updated }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_preferred_host_image # rubocop:todo GitHub/UseRestfulActions
    user_settings = Codespaces::Settings.for_user(current_user)
    host_image_updated = user_settings.update({ preferred_host_image: params[:codespace_preferred_host_image] })
    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/host_image", locals: { show_check: host_image_updated, show_error: !host_image_updated }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_gpg_authorization # rubocop:todo GitHub/UseRestfulActions
    current_user.update_gpg_authorization(params[:gpg_authorization], actor: current_user)

    # toggle repo authorization
    if params[:repo]
      authorization = current_user.trusted_repository_authorizations.find_by(repository_id: params[:repo])
      if authorization
        authorization.destroy!
      else
        repository = Repositories::Public.find_active!(params[:repo])
        new_authorization = Codespaces::TrustedRepositoryAuthorization.new(user: current_user, repository: repository)

        unless new_authorization.save
          return render_404
        end
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/gpg", locals: { show_check: true }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_codespaces_repository_authorizations # rubocop:todo GitHub/UseRestfulActions
    if params[:repository_authorization]
      current_user.update_codespaces_repository_authorization(params[:repository_authorization], actor: current_user)
    end

    if params[:repo]
      [params[:repo]].flatten.each do |repo|
        authorization = current_user.trusted_repository_authorizations.find_by(repository_id: repo)
        if authorization && params[:delete]
          authorization.destroy!
        elsif !authorization
          repository = Repositories::Public.find_active!(repo)
          new_authorization = Codespaces::TrustedRepositoryAuthorization.new(user: current_user, repository: repository)

          unless new_authorization.save
            return render_404
          end
        end
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/repository_authorizations", locals: { show_check: true }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_codespaces_settings_sync_authorization  # rubocop:todo GitHub/UseRestfulActions
    current_user.update_codespaces_settings_sync_authorization(params[:codespaces_settings_sync_authorization], actor: current_user)

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/settings_sync", locals: { show_check: true }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_trusted_repositories_access # rubocop:todo GitHub/UseRestfulActions
    trusted_repositories_access = params[:trusted_repositories_access]

    if trusted_repositories_access
      begin
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: current_user,
          target: current_user,
          trusted_repo_setting: trusted_repositories_access,
          repo: params[:repo],
          entry_point: :settings_codespaces_controller_update_trusted_repositories_access
        )
      rescue Configurable::CodespaceTrustedRepositories::InvalidRepoAccessArgumentError
        flash_error = "Sorry, that trusted repositories setting isn't valid."
      rescue Codespaces::UpdateTrustedRepositoryAccess::RepositoryNotOwned
        flash_error = "Unable to mark the repository as trusted."
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/trusted_repositories_configuration", locals: {
          trusted_repositories: current_user_trusted_repositories,
          show_check: true,
          flash_error: flash_error
        }, formats: :html
      end
      format.html do
        flash[:error] = flash_error
        redirect_to action: "index"
      end
    end
  end

  def update_default_location # rubocop:todo GitHub/UseRestfulActions
    user_settings = Codespaces::Settings.for_user(current_user)
    previous_default_location = user_settings.default_location
    location_updated = user_settings.update({ default_location: params[:codespace_default_location] })

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/default_location", locals: {
          show_check: location_updated,
          show_error: !location_updated,
          default_location_for_user: user_settings.default_location.blank? ? previous_default_location : user_settings.default_location,
        }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def update_default_idle_timeout # rubocop:todo GitHub/UseRestfulActions
    user_settings = Codespaces::Settings.for_user(current_user)
    idle_timeout_updated = user_settings.update({ default_idle_timeout: params[:codespace_default_idle_timeout].presence&.to_i })

    respond_to do |format|
      format.html_fragment do
        render Codespaces::IdleTimeoutComponent.new(
          entity: current_user,
          update_idle_timeout_path: settings_user_codespaces_update_default_idle_timeout_path,
        ), formats: :html
      end
      format.html do
        if idle_timeout_updated
          flash[:notice] = "Your idle timeout has been updated."
        else
          flash[:error] = "Your idle timeout could not be updated. Please contact support."
        end

        redirect_to action: "index"
      end
    end
  end

  def update_default_retention_period # rubocop:todo GitHub/UseRestfulActions
    user_settings = Codespaces::Settings.for_user(current_user)

    # retention period comes in from the form in days
    retention_period_updated = user_settings.update({
      default_retention_period: params[:codespace_default_retention_period].blank? ? nil : params[:codespace_default_retention_period].to_i.days.in_minutes.to_i
    })

    respond_to do |format|
      format.html_fragment do
        render Codespaces::RetentionPeriodComponent.new(
          entity: current_user,
          update_retention_period_path: settings_user_codespaces_update_default_retention_period_path,
        ), formats: :html
      end
      format.html do
        if retention_period_updated
          flash[:notice] = "Your retention period has been updated."
        else
          flash[:error] = "Your retention period could not be updated. Please contact support."
        end
        redirect_to action: "index"
      end
    end
  end

  def update_dotfiles_repository # rubocop:todo GitHub/UseRestfulActions
    flash_message = { message: "Changes saved", scheme: :success }
    begin
      current_user.update_codespace_dotfiles_repository(params[:repo], actor: current_user)
    rescue ActiveRecord::RecordNotFound
      flash_message = { message: "Could not update dotfiles repository.", scheme: :danger }
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/codespaces/dotfiles", locals: {
          flash_message: flash_message,
          show_check: true,
        }, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  private

  def public_key(user)
    Secrets.github_public_key(owner: user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
  end

  def grouped_options_for_default_location
    Codespaces::Locations::Geo.public.group_by(&:group_name).map do |group_name, geos|
      [group_name, geos.map { |geo| [geo.name, geo.primary_region.id] }]
    end
  end

  def require_user_codespace_settings_feature
    render_404 unless current_user&.codespaces_feature_enabled?
  end

  def current_user_trusted_repositories
    current_user.integration_installations.find_by(integration: Apps::Privileged.integration(:codespaces_production))&.repositories || []
  end
end
