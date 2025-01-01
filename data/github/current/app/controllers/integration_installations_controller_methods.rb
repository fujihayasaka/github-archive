# typed: true
# frozen_string_literal: true

module IntegrationInstallationsControllerMethods
  extend ActiveSupport::Concern
  include IntegrationInstallationsControllerStateHelper
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :login_required
    before_action :sudo_filter, except: :index

    before_action :require_out_of_date_installation, only: [:update_permissions]
    before_action :ensure_app_has_not_changed, only: [:update, :update_permissions]

    helper_method :current_context
  end

  class InstallationError < StandardError; end

  def index
    view = create_view_model(
      IntegrationInstallations::IndexView,
      target: current_context,
      page: current_page,
    )

    view.execute_queries

    render "integration_installations/index", locals: { view: view }
  end

  def show
    if installation.repository_installation_required?
      if params[:repository_ids]
        if installation.installed_on_all_repositories?
          flash[:notice] = "#{installation.integration.name} is already installed as suggested."
        else
          repository_ids = Array(params[:repository_ids]).map { |value| ActiveModel::Type::Integer.new.cast(value) }.compact

          @integration_installation_request = IntegrationInstallationRequest.ephemeral(
            integration: integration,
            target: target,
            repositories: find_requested_repositories(repository_ids),
          )
        end
      end
    end

    view = create_view_model(
      IntegrationInstallations::ShowView,
      installation: installation,
      installation_request: integration_installation_request
    )
    render "integration_installations/show", locals: { view: view }
  end

  def update
    result = Integration::InstallationService.perform(
      integration: integration,
      installation: installation,
      target: target,
      actor: current_user,
      pending_request: integration_installation_request,
      params: installation_service_params,
      max_installable: Integration::InstallationService::DEFAULT_MAX_REPOS,
      entry_point: :integration_installation_controller_update,
    )

    if result.failed?
      flash[:error] = result.error
      view = create_view_model(
        IntegrationInstallations::SuggestionsView,
        target: target,
        integration: integration,
        session: session
      )
      render "integration_installations/permissions", locals: { view: view }
      return
    end

    if integration_installation_request
      redirect_to gh_settings_installation_path(result.installation_result.installation),
        notice: "Okay, the requested changes to #{ integration.name } were approved and performed for the @#{ target.display_login } account."
    else
      installer_redirect = Integration::InstallerRedirect.new(
        integration: integration,
        installation: installation,
        action: :update,
        return_to_url: session.delete(:return_to_after_installation),
        referring_sha: session.delete(:referring_sha_for_installation),
        setup_state_cookie: IntegrationInstallation::SetupStateCookie.new(cookie_jar: cookies),
      )

      if installer_redirect.should_redirect?
        if integration.can_request_oauth_on_install?
          @access = build_access_after_installation_update(integration, installation)
          installer_redirect.oauth_access = @access
        end

        redirect_url = installer_redirect.url
        IntegrationInstallation::SetupStateCookie.delete(cookie_jar: cookies)

        render "integration_installations/setup_redirect",
          layout: "layouts/redirect",
          locals: { redirect_url: redirect_url, integration: integration }
      else
        redirect_to gh_settings_installation_path(result.installation_result.installation),
          notice: "Okay, #{ integration.name } was updated for the @#{ target.display_login } account."
      end
    end
  end

  def destroy
    UninstallIntegrationInstallationJob.perform_later(current_user.id, installation.id)

    redirect_to gh_settings_installations_path(current_context), notice: "You're all set! A job has been queued to uninstall the '#{integration.name}' app."
  end

  def permissions_update_request
    if installation.outdated?
      view = create_view_model(
        IntegrationInstallations::PermissionsUpdateRequestView,
        installation: installation
      )
      render "integration_installations/permissions_update_request", locals: { view: view }
    else
      view = create_view_model(
        IntegrationInstallations::PermissionsUpdateRequestView,
        installation: installation
      )
      render "integration_installations/permissions_already_up_to_date", locals: { view: view }
    end
  end

  def update_permissions
    result = update_installation(
      update_permissions: true,
      update_repositories: installation.upgrading_from_no_repo_permissions?,
      install_target: params[:install_target],
      repository_ids: params[:repository_ids],
      version_id: params[:version_id],
      entry_point: :integration_installation_controller_update_permissions,
    )

    case result.status
    when :success
      flash[:notice] = "Okay, #{integration.name} was updated for the @#{target.display_login} account."
    when :editor_error, :input_error
      flash.now[:error] = result.error
      view = create_view_model(
        IntegrationInstallations::PermissionsUpdateRequestView,
        installation: installation
      )
      return render "integration_installations/permissions_update_request", locals: { view: view }
    when :permissions_error
      flash.now[:error] = result.error
    end

    redirect_to gh_settings_installation_path(installation)
  end

  def suspend
    result = IntegrationInstallation::Permissions.check(installation: installation, actor: current_user, action: :suspend)

    if result.permitted?
      installation.suspend!(user: current_user)
    else
      flash[:error] = result.error_message
    end

    redirect_to gh_settings_installation_path(installation)
  end

  def unsuspend
    result = IntegrationInstallation::Permissions.check(installation: installation, actor: current_user, action: :unsuspend)

    if result.permitted?
      installation.unsuspend!(user: current_user)
      flash[:notice] = "Your app has been unsuspended"
    else
      flash[:error] = result.error_message
    end

    redirect_to gh_settings_installation_path(installation)
  end

  # GET /settings/installations/{id}/repositories
  #
  # Shows which of the target's repositories the installation has been granted
  # access to.
  def repositories
    view = create_view_model(
      IntegrationInstallations::ShowView,
      installation: installation,
    )

    org_repo_index_view = create_view_model(
      Orgs::Repositories::IndexPageView,
      organization: installation.target,
      current_page: current_page,
      type_filter: params[:type],
      sort_order: params[:sort],
      phrase: search_query,
      language: params[:language],
      view_as: params[:view_as],
    )

    repo_access_filter = IntegrationInstallation::RepositoryAccessFilter.new(
      installation_show_view: view,
      org_repo_index_view: org_repo_index_view,
    )

    if request.xhr? || pjax?
      # Show the partial with two columns
      # This is in response to a search query
      render partial: "integration_installations/repositories/columns", locals: { view: repo_access_filter }
    else
      render "integration_installations/repositories", locals: { view: repo_access_filter }
    end
  end

  private

  def installation
    @installation ||= current_context.
      integration_installations.
      # non user-installable internal GitHub Apps should never be
      # viewed/edited/managed by end-users.
      user_installable.
      preload(:integration, :target).
      find(params[:id])
  end

  def integration_installation_request
    @integration_installation_request ||= IntegrationInstallationRequest.find_by(
      id:          params[:request_id],
      integration: integration,
      target:      target,
    )
  end

  def integration
    @integration ||= installation.integration
  end

  alias_method :current_integration, :integration

  def target
    @target ||= installation.target
  end

  # Private: Returns the correct target depending on if we're working
  # with org or user integrations.
  #
  # Returns an Organization or a User
  def current_context
    raise NotImplementedError
  end

  def target_for_conditional_access
    target = current_context
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def require_out_of_date_installation
    unless installation.outdated?
      render_404
    end
  end

  def installation_service_params
    params.to_unsafe_h.with_indifferent_access.slice :install_target,
                                                     :integration_installation,
                                                     :repository_ids,
                                                     :version_id
  end

  # Internal: Update an installation's permissions, repositories or both.
  #
  # update_permissions  - Boolean. Should the installation's permissions be
  #                       updated to the latest version?
  # update_repositories - Boolean. Should the installation's repositories be
  #                       updated based on the controller params.
  # install_target      - String. (Optional) One of "all" or "select".
  # repository_ids      - Array. (Optional) List of repo IDs to select for this
  #                       installation.
  # version_id          - Integer. (Optional) The IntegrationVersion to
  #                       install.
  # entry_point         - Symbol. The entry point to tag permission writes with
  #
  # Returns a IntegrationInstallation::UpdateResult.
  def update_installation(update_permissions: false, update_repositories: false, install_target: nil, repository_ids: nil, version_id: nil, entry_point:)
    result = IntegrationInstallation::UpdateResult.argument_error(message: "update permissions or update repositories", installation: installation)
    return result if !update_permissions && !update_repositories

    if update_permissions
      permissions_result = installation.update_version(
        editor: current_user,
        version: installation.integration.versions.find_by_id(version_id) || installation.integration.latest_version,
        entry_point: entry_point
      )

      if permissions_result.success?
        result = IntegrationInstallation::UpdateResult.success(installation: installation)
      else
        return IntegrationInstallation::UpdateResult.permissions_error(
          message: permissions_result.error,
          installation: installation,
        )
      end
    end

    if update_repositories
      case install_target
      when "selected"
        if repository_ids.blank?
          return IntegrationInstallation::UpdateResult.input_error(
            message: "Please select at least one repository to install on",
            installation: installation,
          )
        end
        repos = target.repositories.where(id: repository_ids)
        if repos.blank?
          return IntegrationInstallation::UpdateResult.input_error(
            message: "Repositories must be owned by #{target.display_login}",
            installation: installation,
          )
        end
      when "all"
        repos = nil
      else
        return IntegrationInstallation::UpdateResult.input_error(
          message: "Please select individual or all repositories",
          installation: installation,
        )
      end

      editor_result = installation.edit(
        editor: current_user,
        repositories: repos,
        entry_point: :integration_installation_controller_update_installation,
      )

      if editor_result.success?
        result = IntegrationInstallation::UpdateResult.success(installation: installation)
      else
        return IntegrationInstallation::UpdateResult.editor_error(
          message: editor_result.error,
          installation: installation,
        )
      end
    end

    result
  end

  def find_requested_repositories(repo_ids)
    return IntegrationInstallationRequest::ALL_REPOS unless repo_ids.present?

    available_repo_ids = repo_ids & (
      integration.installable_repository_ids_on_by(target: target, actor: current_user) +
      integration.requestable_repository_ids_on_by(target: target, actor: current_user)
    )

    if FeatureFlag.vexi.enabled?(:repos_domain_find, default: false)
      repos = Repositories.domain.by_ids(available_repo_ids).to_a
      raise ActiveRecord::RecordNotFound if available_repo_ids.count != repos.count
      repos
    else
      Repository.find(available_repo_ids)
    end
  end

  def app_changed_since_last_viewed(action)
    case action
    when "update", "update_permissions"
      redirect_to gh_settings_installation_path(installation)
    end
  end

  def build_access_after_installation_update(integration, installation)
    authorization = current_user.oauth_authorizations.where(application: integration).first
    return unless authorization.present?

    integration.grant(
      current_user,
      { integration_version_number: authorization.integration_version.number, user_session: user_session, entry_point: :integration_installation_controller_build_access_after_installation },
    )
  end

  def search_query
    return @search_query if defined? @search_query

    raw_query = params[:q]
    @search_query = raw_query if raw_query.is_a?(String)
  end
end
