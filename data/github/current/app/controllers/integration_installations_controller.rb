# typed: true
# frozen_string_literal: true

class IntegrationInstallationsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:permissions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:new, :select_target]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    only: [:edit_permissions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :permissions, :edit, :edit_permissions, :select_target],
    optional: true

  class InstallationError < StandardError; end

  include IntegrationInstallationsControllerStateHelper

  before_action :reject_applications_owned_by_spammy!
  before_action :authorization_required, only: [:new, :permissions, :suggestions, :select_target]
  before_action :sudo_filter, except: [:new, :permissions, :suggestions, :select_target]
  before_action :find_installation, only: [:edit, :update, :edit_permissions, :update_permissions]
  before_action :find_target, except: [:new, :select_target]
  before_action :find_version, only: [:create, :update_permissions]
  before_action :prevent_multiple_requests, only: [:permissions, :create]
  before_action :track_referrer, only: [:permissions]
  before_action :ensure_app_has_not_changed, only: [:create, :update, :update_permissions]
  before_action :set_setup_state_cookie, only: [:new, :permissions, :select_target]

  javascript_bundle :settings
  stylesheet_bundle :integrations

  MAX_REPOSITORIES_ON_INITIAL_INSTALL = Integration::InstallationService::DEFAULT_MAX_REPOS

  BACKOFF_RETRIES = {
    0 => 0.1,
    1 => 0.250,
    2 => 0.5,
    3 => 1.0,
    4 => 3.0,
  }

  helper_method :current_target

  def new
    if account_switcher_helper.enabled? && account_switcher_helper.stashed_accounts.any?
      render "integration_installations/select_account", layout: "layouts/session_authentication", locals: {
        view: select_view,
        continue_to: gh_app_select_target_path(current_integration, params: request.query_parameters),
        return_to: gh_app_select_target_path(current_integration, params: request.query_parameters),
      }
    else
      redirect_to gh_app_select_target_path(current_integration, params: request.query_parameters)
    end
  end

  def select_target # rubocop:todo GitHub/UseRestfulActions
    if select_view.selection_needed?
      render "integration_installations/select_target", locals: { view: select_view }
    elsif select_view.accounts.none?
      redirect_to gh_app_path(current_integration, current_user)
    else
      account = select_view.accounts.first

      if current_integration.installed_on?(account)
        installation = current_integration.installations.with_target(account).first
        redirect_to gh_settings_installation_path(installation)
      elsif current_user.feature_enabled?(:render_to_single_target_select) && integration_request_exists?(account)
        render "integration_installations/select_target", locals: { view: select_view }
      else
        redirect_to gh_app_installation_permissions_path(
          current_integration,
          current_user,
          target_id: account.id,
        )
      end
    end
  end

  def permissions # rubocop:todo GitHub/UseRestfulActions
    if current_installation.present?
      redirect_params = {}
      redirect_params[:repository_ids] = params[:repository_ids] || "" if params[:suggested_target_id]

      if current_installation.adminable_by?(current_user)
        return redirect_to gh_settings_installation_path(current_installation, redirect_params.merge({ request_id: current_integration_installation_request }))
      end

      if current_integration.installable_on_by?(target: current_target, actor: current_user)
        return redirect_to gh_edit_app_installation_path(current_integration, current_installation, current_user, **redirect_params)
      end
    end

    view = create_view_model(
      IntegrationInstallations::SuggestionsView,
      target: current_target,
      integration: current_integration,
      installation_request: current_integration_installation_request,
      session: session,
      referer: env["HTTP_REFERER"]
    )
    render "integration_installations/permissions", locals: { view: view }
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "integration_installations/suggestions", formats: :html, locals: {
          view: create_view_model(IntegrationInstallations::SuggestionsView,
            target: current_target,
            integration: current_integration,
            installation: current_installation,
            query: params[:q],
            skip_installed_on_check: params[:edit].present?,
            session: session
          )
        }
      end
    end
  end

  def create
    result = Integration::InstallationService.perform(
      integration: current_integration,
      target: current_target,
      actor: current_user,
      pending_request: current_integration_installation_request,
      params: installation_service_params,
      max_installable: MAX_REPOSITORIES_ON_INITIAL_INSTALL,
      entry_point: :integration_installation_controller_create,
    )

    if result.failed?
      flash[:error] = result.error.to_s
      view = create_view_model(
        IntegrationInstallations::SuggestionsView,
        target: current_target,
        integration: current_integration,
        session: session
      )
      return render "integration_installations/permissions", locals: { view: view }
    end

    installation_result = result.installation_result
    request_result = result.request_result

    # If we weren't able to perform a request or an installation send the
    # user back to the new installation page to try again.
    if !installation_result&.success? && !request_result&.valid?
      error = InstallationError.new("Failed to install #{current_integration.name} on #{current_target.display_login}")
      error.set_backtrace(caller)
      Failbot.report!(error, app: "github-apps")

      error_message = "Something went wrong when trying to install #{ current_integration.name } app, please try again"
      return redirect_to gh_new_app_installation_url(current_integration, current_user), error: error_message
    end

    # At this point we know that either an installation was created or an
    # installation request has been sent.
    action = installation_result&.success? ? :install : :request

    # Are we redirecting the current_user outside of GitHub via a callback_url or setup_url?
    @installer_redirect = build_installer_redirect(action: action, installation: installation_result.try(:installation))
    return render_setup_redirect(action: :create) if @installer_redirect.should_redirect?

    if action == :request
      notice = "A request to install #{ current_integration.name } has been submitted on the @#{ current_target.display_login } account."
      return redirect_to gh_new_app_installation_url(current_integration, current_user), notice: notice
    end

    notice = "Okay, #{ current_integration.name } was installed on the @#{ current_target.display_login } account."

    settings_path = if installation_result.installation.adminable_by?(current_user)
      gh_settings_installation_path(installation_result.installation)
    else
      gh_edit_app_installation_path(current_integration, installation_result.installation, current_user)
    end

    redirect_to settings_path, notice: notice
  end

  # Accessible to non-admins for the installation target account, such as
  # repository admins.
  #
  # Target account admins use installation settings endpoints that are context
  # specific.
  def edit
    view = create_view_model(
      IntegrationInstallations::ShowView,
      installation: current_installation,
      installation_request: current_integration_installation_request
    )
    render "integration_installations/edit", locals: { view: view }
  end

  # Accessible to non-admins for the installation target account, such as
  # repository admins.
  #
  # Target account admins use installation settings endpoints that are context
  # specific.
  def update
    result = Integration::InstallationService.perform(
      integration: current_integration,
      installation: current_installation,
      target: current_target,
      actor: current_user,
      params: installation_service_params.merge(install_target: "selected"),
      max_installable: MAX_REPOSITORIES_ON_INITIAL_INSTALL,
      editor: :repository_editor,
      entry_point: :integration_installation_controller_update,
    )

    if result.failed?
      flash[:error] = result.error
      return edit
    end

    if current_installation.destroyed?
      redirect_to gh_app_installation_permissions_path(current_integration, current_user, target_id: current_target.id),
        notice: "Okay, #{ current_integration.name } was uninstalled from the @#{ current_target.display_login } account."
    else
      # Are we redirecting the current_user outside of GitHub via a callback_url or setup_url?
      @installer_redirect = build_installer_redirect(action: :update, installation: current_installation)
      return render_setup_redirect(action: :update) if @installer_redirect.should_redirect?

      redirect_to gh_edit_app_installation_path(current_integration, current_installation, current_user),
        notice: "Okay, #{ current_integration.name } was updated for the @#{ current_target.display_login } account."
    end
  end

  def edit_permissions # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      IntegrationInstallations::PermissionsUpdateRequestView,
      installation: current_installation
    )

    if current_installation.outdated?
      render "integration_installations/permissions_update_request", locals: { view: view }
    else
      render "integration_installations/permissions_already_up_to_date", locals: { view: view }
    end
  end

  def update_permissions # rubocop:todo GitHub/UseRestfulActions
    raise NotFound unless current_installation.outdated?

    permissions_result = current_installation.update_version(
      editor: current_user,
      version: @version,
      entry_point: :integration_installation_controller_update_permissions,
    )

    if permissions_result.success?
      redirect_to gh_edit_app_installation_path(current_integration, current_installation, current_user),
        notice: "Okay, #{ current_integration.name } was updated for the @#{ current_target.display_login } account."
    else
      flash[:error] = permissions_result.error
      edit_permissions
    end
  end

  private

  # Checks if a request for this integration/target already exists
  # Returns true if request exists, false otherwise
  def integration_request_exists?(target)
    IntegrationInstallationRequest.where(
      requester: current_user,
      integration: current_integration,
      target: target
    ).any?
  end

  def access_denied
    args = {}.tap do |arg|
      arg[:return_to]   = request.fullpath
      arg[:integration] = current_integration.slug if current_integration
    end

    redirect_to login_path(args)
  end

  def select_view # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @select_view ||= Integrations::SelectTargetView.new(
      current_user: current_user,
      integration: current_integration,
      page: params[:page] || 1
    )
  end

  def track_referrer
    return unless params[:track_referrer] == "true" && request.post?
    session[:return_to_after_installation] = params[:installation_referrer]
    session[:referring_sha_for_installation] = params[:installation_referring_sha]
  end

  def installation_service_params
    params.to_unsafe_h.with_indifferent_access.slice :install_target,
                                                     :integration_installation,
                                                     :repository_ids,
                                                     :version_id
  end

  def current_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    if installing_external_app?
      integration = Integration.user_installable.find_by!(slug: params[:integration_id])

      return @integration = integration if integration.synchronized_dotcom_app?
      raise ActiveRecord::RecordNotFound
    end

    @integration ||= Integration.from_owner_and_slug!(
      viewer:        current_user,
      slug:          params[:integration_id],
      user_login:    params[:owner],
      business_slug: params[:slug],
    )
  end

  # TODO: This method is duplicated in
  # Integrations::InstallationActionsController. If you ever feel tempted to
  # duplicated this code then it's time to extract it.
  def installing_external_app?
    return false unless GitHub.multi_tenant_enterprise?

    app_prefix = GitHub.enterprise? ? "github-apps" : "apps"
    external_app_path = "/#{app_prefix}/#{GitHub.proxima_external_apps_owner_slug}"

    request.path.start_with?(external_app_path)
  end

  def current_integration_installation_request # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    if params[:suggested_target_id] || (current_installation && params[:repository_ids])
      repository_ids = Array(params[:repository_ids]).map { |value| ActiveModel::Type::Integer.new.cast(value) }.compact

      @installation_request ||= IntegrationInstallationRequest.ephemeral(
        integration: current_integration,
        target: current_target,
        repositories: find_requested_repositories(repository_ids),
      )
    end

    return @installation_request unless current_target.adminable_by? current_user

    @installation_request ||= IntegrationInstallationRequest.find_by(
      id:          params[:request_id],
      integration: current_integration,
      target:      current_target,
    )
  end

  def find_requested_repositories(repo_ids)
    return IntegrationInstallationRequest::ALL_REPOS unless repo_ids.present?

    available_repo_ids = repo_ids & (
      current_integration.installable_repository_ids_on_by(target: current_target, actor: current_user) +
      current_integration.requestable_repository_ids_on_by(target: current_target, actor: current_user)
    )

    Repository.find(available_repo_ids)
  end

  memoize def current_target
    return target_from_params if current_installation.nil?

    current_installation.target
  end

  memoize def current_installation
    if params[:id]
      current_integration.installations.find_by(id: params[:id])
    else
      current_integration.installations.find_by(target: target_from_params)
    end
  end

  memoize def target_from_params
    target_id = params[:target_id] || params[:suggested_target_id]

    if params[:target_type] == "Business"
      Business.find_by(id: target_id)
    else
      User.find_by(id: target_id)
    end
  end

  def find_installation
    raise NotFound unless current_installation&.viewable_by?(current_user)

    return redirect_to gh_settings_installation_path(current_installation) if current_installation.adminable_by?(current_user)

    current_installation
  end

  def prevent_multiple_requests
    if integration_request_exists?(current_target)
      flash[:error] = "A request to #{ current_target.display_login } already exists, cancel before submitting a new one or wait for an administrator to respond"
      redirect_to gh_new_app_installation_url(current_integration, current_user)
    end
  end

  def reject_applications_owned_by_spammy!
    render_404 if current_integration&.hide_from_user?(current_user)
  end

  def find_target
    raise NotFound if current_target.nil?

    installable = current_integration.installable_on_by?(target: current_target, actor: current_user)
    requestable = current_integration.requestable_on_by?(target: current_target, actor: current_user)

    raise NotFound unless installable || requestable

    current_target
  end

  def find_version
    @version = current_integration.versions.find_by!(id: params[:version_id])
  end

  def ip_allowlist_enforceable
    return :no if params[:action] == "new"
    super
  end

  # Opting out from or enforcing conditional access policies is handled in this method
  def external_conditional_access_policy_enforceable
    return :no if params[:action] == "new"
    super
  end

  def require_active_external_identity_session?
    return false if params[:action] == "new"
    super
  end

  def two_factor_enforceable
    return :no if params[:action] == "new"
    :yes
  end

  # We can safely skip the `perform_conditional_access_checks` filter
  # for the following actions:
  # - new: this action doesn't directly access an organization; it either
  #        allows the user to select an account to install on, or redirects
  #        to the appropriate installation endpoint where enforcement is
  #        handled.
  def target_for_conditional_access
    target = current_target
    return :no_target_for_conditional_access unless target.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def set_setup_state_cookie
    if params[:state] && current_integration
      IntegrationInstallation::SetupStateCookie.create(
        cookie_jar: cookies,
        data: { state: params[:state] },
        integration_id: current_integration.global_relay_id,
        target_id: params[:target_id] || params[:suggested_target_id],
      )
    end
  end

  # Internal: The path to redirect a user to if the action they are trying to
  # take should not be completed because the GitHub App has been updated since
  # they last loaded the page. This prevents a user from accepting
  # installations/permissions based on out of date information.
  #
  # action  - String. The controller action that was halted due to a changed
  #           App.
  #
  # Returns either a redirect_to or render.
  def app_changed_since_last_viewed(action)
    case action
    when "create"
      redirect_to gh_new_app_installation_url(current_integration, current_user)
    when "update"
      redirect_to gh_settings_installation_path(current_installation)
    when "update_permissions"
      edit_permissions
    end
  end

  def build_installer_redirect(action:, installation: nil)
    Integration::InstallerRedirect.new(
      integration: current_integration,
      installation: installation,
      action: action,
      return_to_url: session.delete(:return_to_after_installation),
      referring_sha: session.delete(:referring_sha_for_installation),
      setup_state_cookie: IntegrationInstallation::SetupStateCookie.new(cookie_jar: cookies),
    )
  end

  def render_setup_redirect(action:)
    if current_integration.can_request_oauth_on_install?
      if action == :create
        @access = current_integration.grant(current_user, {
          integration_version_number: @version.number,
          user_session: user_session,
          entry_point: :integration_installation_controller_render_setup_redirect_create
        })
      else
        authorization = current_user.oauth_authorizations.where(application: current_integration).first
        if authorization.present?
          @access = current_integration.grant(current_user, {
            integration_version_number: authorization.integration_version.number,
            user_session: user_session,
            entry_point: :integration_installation_controller_render_setup_redirect_update
          })
        end
      end
    end

    @installer_redirect.oauth_access = @access
    redirect_url = @installer_redirect.url

    IntegrationInstallation::SetupStateCookie.delete(cookie_jar: cookies)

    render "integration_installations/setup_redirect", layout: "layouts/redirect",
      locals: { redirect_url: redirect_url, integration: current_integration }
  end

  def max_pagination_page
    return GitHub.max_ui_pagination_page unless action_name == "select_target"

    params[:page].to_i + 10
  end
end
