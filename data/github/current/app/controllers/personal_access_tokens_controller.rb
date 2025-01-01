# typed: true
# frozen_string_literal: true

class PersonalAccessTokensController < ApplicationController
  include SsoHelper
  include GranularPermissionsHelper

  before_action :login_required
  before_action :require_programmatic_access_tokens_enabled
  before_action :sudo_filter, except: [:index, :expiration, :suggestions, :select_access]
  before_action :check_eligibility, only: [:new, :create]

  before_action :ensure_current_access, except: [:index, :new, :create, :select_access, :suggestions, :preview_grant_request_reason]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show, :new, :index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:expiration]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:regenerate_edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:select_access]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :show, :regenerate_edit, :expiration], optional: true

  BETA_VERSION = "beta"

  PER_PAGE = 10

  ACTIONS_USING_ACCESS_AS_RFCA = %w(destroy expiration update)
  ACTIONS_USING_TARGET_AS_RFCA = %w(create preview_grant_request_reason regenerate_edit regenerate select_access show suggestions)

  javascript_bundle :settings
  stylesheet_bundle :settings

  helper_method :current_access, :current_grant, :current_grant_request, :current_target, :null_grant, :request_reason

  def index
    context_region_preset :developer_settings

    tokens = ProgrammaticAccess.for(current_user)
      .order(created_at: :desc)
      .paginate(page: current_page, per_page: PER_PAGE)

    render "personal_access_tokens/index", locals: { tokens: tokens }
  end

  def new
    context_region_preset :developer_settings

    access = ProgrammaticAccess.new_access(current_user)

    if current_target.user?
      permissions_view, repositories_view = generate_form_views(access)

      render "personal_access_tokens/new", locals: {
        token: access,
        permissions_view: permissions_view,
        repositories_view: repositories_view
      }
    else
      render "personal_access_tokens/new", locals: { token: access }
    end
  end

  def create
    unless current_target.patsv2_enabled?
      flash[:error] = "You do not have permission to create PATs for this account."
      return redirect_to settings_user_access_tokens_path
    end

    options = {
      actor: current_user,
      target: current_target,
      access_token_attributes: access_token_params,
      permissions: requested_permissions,
      repositories: requested_repositories,
      repository_selection: repository_selection_type,
      entry_point: :personal_access_tokens_controller_create,
    }

    if params[:confirm] != "1"
      access = ProgrammaticAccess.new_access(current_user, options.delete(:access_token_attributes))
      access.issued_at = Time.zone.now
      access.set_expiration(
        access_token_params[:default_expires_at],
        access_token_params[:custom_expires_at],
        allow_custom_default_expires_at: ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(current_target, access.pat_type)
      )
      grantable = ProgrammaticAccessGrantRequest::Service.new(options)

      return render("personal_access_tokens/confirmation_dialog", locals: {
        token: access,
        grantable: grantable,
        repository_permissions: Repository::Resources.filter(grantable.permissions),
        account_permissions: User::Resources.filter(grantable.permissions),
        organization_permissions: Organization::Resources.filter(grantable.permissions),
        requesting_access: !ProgrammaticAccessGrantRequest.approvable_by?(current_target, current_user)
      })
    end

    if request_reason && current_target.organization?
      options[:request_reason] = request_reason
    end

    result = ProgrammaticAccess.create_with_grant_and_token(options)

    if result.errors.any?
      if result.errors.where(:owner, :too_many).any?
        flash[:error] = result.errors.full_messages.to_sentence
      elsif result.grantable && result.grantable.errors.any?
        flash[:error] = result.grantable.errors.full_messages.to_sentence
      end

      permissions_view, repositories_view = generate_rerendered_form_views(result)
      return render "personal_access_tokens/new", locals: {
        token: result.access,
        current_target: current_target,
        permissions_view: permissions_view,
        repositories_view: repositories_view,
        errors: result.errors,
        rerender: true,
      }
    end

    token_result = result.token_result
    flash[:new_access] = {
      id: result.access.id, token: token_result.value, success: token_result.success?
    }
    redirect_to settings_user_access_tokens_path
  end

  def show
    permissions_view, repositories_view = generate_form_views(current_access)

    render "personal_access_tokens/show", locals: {
      token: current_access,
      permissions_view: permissions_view,
      repositories_view: repositories_view
    }
  end

  def update
    current_access.update(access_token_params)
    render partial: "personal_access_tokens/token_form", locals: { token: current_access }
  end

  def regenerate_edit # rubocop:todo GitHub/UseRestfulActions
    render "personal_access_tokens/regenerate_edit", locals: { token: current_access }
  end

  def regenerate # rubocop:todo GitHub/UseRestfulActions
    current_access.issued_at = Time.zone.now
    current_access.set_expiration(
      params.dig(:user_programmatic_access, :default_expires_at),
      params.dig(:user_programmatic_access, :custom_expires_at),
      allow_custom_default_expires_at: allow_custom_default_expires_at?
    )

    if current_access.errors.any?
      return render "personal_access_tokens/regenerate_edit",
        locals: { token: current_access }
    end

    regeneration_result = ProgrammaticAccess::TokenManager.regenerate(
      current_access,
      current_access.expires_at
    )

    if regeneration_result.success?
      # Do not remove this custom metric. It's being used by this action's SLO.
      GitHub.dogstats.increment("personal_access_tokens.regenerate", tags: ["result:success"])
      current_access.instrument_regeneration(regeneration_result)

      flash[:new_access] = {
        id: current_access.id,
        token: regeneration_result.value,
        success: true
      }
    else
      flash[:error] = "An error occurred when regenerating this token, please try again"
    end

    if params[:index_page].present?
      page_num = params[:index_page]
      redirect_to settings_user_access_tokens_path(page: page_num)
    else
      redirect_to settings_user_access_token_path
    end
  end

  def destroy
    result = ProgrammaticAccess.destroy(current_access, :web_user)
    if result.success?
      # Do not remove this custom metric. It's being used by this action's SLO.
      GitHub.dogstats.increment("personal_access_tokens.destroy", tags: ["result:success"])
      flash[:notice] = "Deleted personal access token"
    else
      flash[:error] = "Your token was unable to be deleted"
    end
    redirect_to settings_user_access_tokens_path
  end

  def expiration # rubocop:todo GitHub/UseRestfulActions
    expiration_result = ProgrammaticAccess::TokenManager.expiration_for(current_access)
    return head :service_unavailable if expiration_result.failed?

    regeneration_path = edit_regenerate_user_access_token_path(
      current_access,
      index_page: params[:page] || "1"
    )

    render PersonalAccessTokens::ExpirationInfoComponent.new(
      expiration_time: expiration_result.value,
      regeneration_path: regeneration_path
    ), layout: false
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_target.patsv2_enabled?

    respond_to do |format|
      format.html_fragment do
        new_access = ProgrammaticAccess.new_access(current_user)

        render partial: "integration_installations/suggestions", formats: :html, locals: {
          view: create_view_model(IntegrationInstallations::SuggestionsView,
            target: current_target,
            programmatic_access: current_access || new_access,
            query: params[:q],
            skip_installed_on_check: params[:edit].present?,
            session: session
          )
        }
      end
    end
  end

  def select_access # rubocop:todo GitHub/UseRestfulActions
    unless current_target.organization?
      return render_partial_to_select_access
    end

    if signed_token_authed? || external_identity_session_fresh?
      return render_partial_to_select_access
    end

    return_to_url =
      if current_access&.persisted?
        settings_user_access_token_url(id: current_access.id, target_name: current_target.display_login)
      else
        new_settings_user_access_token_url(target_name: current_target.display_login)
      end

    sso_path = external_identity_target_sso_path(
      current_target.external_identity_session_owner,
      return_to: return_to_url
    )

    render partial: "personal_access_tokens/unauthorized", locals: { authorization_path: sso_path }
  end

  def preview_grant_request_reason # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_target.organization?

    record = ProgrammaticAccessGrantRequest.preview_reason(current_target, params[:text])
    render html: record.body_html
  end

  private

  def access_token_params
    params
      .require(:user_programmatic_access)
      .permit(:name, :description, :default_expires_at, :custom_expires_at)
  end

  memoize def current_access
    return unless params[:id]
    ProgrammaticAccess.for(current_user).find_by(id: params[:id])
  end

  memoize def current_grant
    current_access&.grant
  end

  memoize def current_grant_request
    current_access&.grant_request
  end

  memoize def current_target
    if grantable = (current_grant || current_grant_request)
      target = grantable.target
      raise ActiveRecord::RecordNotFound unless target

      return target
    end

    if params[:target_name].present? && params[:target_name] != current_user.display_login
      current_user.organizations.find_by!(login: params[:target_name])
    else
      current_user
    end
  end

  def ensure_current_access
    render_404 unless current_access
  end

  memoize def null_grant
    access = current_access || ProgrammaticAccess.new_access(current_user)
    ProgrammaticAccessGrant.null_grant(access, current_target)
  end

  def requested_permissions
    return current_grant_request.permissions if current_grant_request

    params
      .require(:integration)
      .permit(default_permissions: {})
      .to_h
      .fetch(:default_permissions)
      .delete_if { |_, action| action_blank?(action) }
      .transform_values!(&:to_sym)
  end

  def request_reason
    params[:reason].present? ? params[:reason] : nil
  end

  def repository_selection_type
    return :none unless params[:install_target].present?

    target = params[:install_target].to_sym
    target == :selected ? :subset : target
  end

  def requested_repositories
    current_target.repositories.where(id: Array(params[:repository_ids]))
  end

  def generate_form_views(access)
    permissions_view = create_view_model(::Integrations::PermissionsView,
      programmatic_access: access,
      disabled_for_all_actions: access.has_requested_grant?
    )

    repositories_view = create_view_model(IntegrationInstallations::SuggestionsView,
      programmatic_access: access,
      target: current_target,
    )

    [permissions_view, repositories_view]
  end

  def generate_rerendered_form_views(result)
    access = result.access
    permissions_view = create_view_model(::Integrations::PermissionsView,
      programmatic_access: access,
      programmatic_access_requested_permissions: requested_permissions,
      disabled_for_all_actions: access.has_requested_grant?
    )

    repositories_view = create_view_model(IntegrationInstallations::SuggestionsView,
      programmatic_access: access,
      target: current_target,
      programmatic_access_repository_selection_type: repository_selection_type,
      programmatic_access_requested_repositories: requested_repositories,
      errors: result.errors,
    )

    [permissions_view, repositories_view]
  end

  def target_for_conditional_access
    # Borrowed from `Settings::ControllerMethods#target_for_conditional_access
    #
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    unless current_user
      GitHub.logger.info(
        "Logged in was true but current_user was nil",
        "gh.request_id" => GitHub.context[:request_id],
      )

      return :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    resource =
      if ACTIONS_USING_TARGET_AS_RFCA.include?(action_name)
        current_target
      elsif ACTIONS_USING_ACCESS_AS_RFCA.include?(action_name) && current_access
        current_access
      else
        current_user
      end

    resource.target_for_conditional_access
  end

  def require_programmatic_access_tokens_enabled
    render_404 unless current_user.patsv2_enabled?
  end

  def check_eligibility
    return unless current_user.must_verify_email?

    flash[:error] = "Creating a personal access token requires a verified email address."
    render_email_verification_required
  end

  def require_active_external_identity_session?
    action_name != "select_access"
  end

  def render_partial_to_select_access
    if current_access&.persisted?
      permissions_view, repositories_view = generate_form_views(current_access)

      render partial: "personal_access_tokens/reselect_access", locals: {
        token: current_access, permissions_view: permissions_view, repositories_view: repositories_view,
      }
    else
      access = ProgrammaticAccess.new_access(current_user)
      permissions_view, repositories_view = generate_form_views(access)

      render partial: "personal_access_tokens/select_access", locals: {
        token: access, permissions_view: permissions_view, repositories_view: repositories_view,
      }
    end
  end

  def allow_custom_default_expires_at?
    grant_target = current_access.grant&.target || current_access.grant_request&.target
    ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(grant_target, current_access.pat_type).present?
  end
end
