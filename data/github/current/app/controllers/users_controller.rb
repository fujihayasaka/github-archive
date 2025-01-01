# typed: true
# frozen_string_literal: true

class UsersController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:user_profile_menu]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:billing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    only: [:organizations_info]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  PUBLIC_PRIVATE_CONTRIBUTION_SETTING_FLASH = "Visitors will now see your public and anonymized private contributions. ".freeze
  PUBLIC_CONTRIBUTION_SETTING_FLASH = "Visitors will now see only your public contributions. ".freeze

  include ActionView::Helpers::NumberHelper
  include BillingSettingsHelper
  include SuggestedUsernamesHelper
  include ApplicationController::VerifiedFetchDependency

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  allow_verified_fetch only: [:dismiss_notice, :dismiss_repository_notice, :set_protocol]

  # Exempt specific actions from the GHES first run check to allow the
  # password to be checked when no users exist.
  skip_before_action :first_run_check, only: %w(password_check) if GitHub.enterprise?

  before_action :ensure_billing_enabled, only: %[billing]
  before_action :delete_sponsorship_rollback_notice, only: %[billing]

  # How many actions does this thing have? What about some :except?
  before_action :login_required, only: %w( edit update change_password
                                           billing destroy rename
                                           dismiss_notice set_protocol
                                           set_private_contributions_preference
                                           organizations_info
                                           dismiss_repository_notice
                                           rename_check
                                           user_profile_menu )

  before_action only: [:destroy] do
    T.bind(self, UsersController)
    check_trade_compliance(redirect_url: settings_account_preferences_path)
    ensure_trade_screening_status_allows_deletion
  end

  before_action :ensure_valid_email, only: [:update, :change_password]
  before_action :sudo_filter, only: :destroy
  before_action :require_xhr, only: [:organizations_info, :user_profile_menu]
  before_action :find_new_repository_owner, only: :organizations_info

  UPDATE_ACTIONS = %w(update)
  CHANGE_PASSWORD_ACTIONS = %w(change_password)
  RENAME_CHECK_ACTIONS = %w(rename_check)
  RENAME_ACTIONS = %w(rename)

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: UPDATE_ACTIONS + CHANGE_PASSWORD_ACTIONS + RENAME_CHECK_ACTIONS + RENAME_ACTIONS,
    if: :users_rate_limit_filter,
    key: :users_rate_limit_key,
    log_key: :users_rate_limit_log_key,
    max: :users_rate_limit_max,
    ttl: :users_rate_limit_ttl,
    at_limit: :users_rate_limit_record

  def index
    redirect_to "/"
  end

  def edit
    url =
      case params["tab"]
      when "profile"
        settings_user_profile_url
      when "admin"
        settings_account_preferences_url
      when "email"
        settings_email_preferences_url
      when "ssh"
        settings_keys_url
      when "job"
        settings_user_profile_url
      when "connections"
        settings_user_applications_url
      else
        settings_user_profile_url
      end

    redirect_to url
  end

  def update
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    @user = current_user
    @selected_tab = params[:tab]
    user_params = params.require(:user)
    private_contribs = user_params.delete(:show_private_contribution_count)
    if user_feature_enabled?(:private_profile_setting)
      private_profile = user_params.delete(:private_profile)
    end
    # If the opt-in checkbox (profile_display_local_time_zone) is unchecked, the
    # time zone (profile_local_time_zone_name) has to be erased
    unless user_params.delete(:profile_display_local_time_zone)
      user_params[:profile_local_time_zone_name] = nil
    end
    enable_pro_badge = user_params.delete(:pro_badge_enabled)

    SocialAccounts::AcceptSocialAccountParameters.call(user: current_user, params: user_params)
    user_params.delete(:profile_social_accounts)

    if GitHub.orcid_enabled?
      # Normalize :display_orcid_on_profile parameter to be a Boolean, false if it's absent
      user_params[:display_orcid_id_on_profile] = !!user_params[:display_orcid_id_on_profile]
    end

    permitted_user_params = %i[
      profile_name
      profile_email
      profile_blog
      profile_company
      profile_location
      profile_hireable
      profile_bio
      public_keys
      wants_email
      gravatar_email
      profile_display_staff_badge
      profile_local_time_zone_name
      profile_spoken_language_preference_code
      profile_pronouns
    ]

    if GitHub.orcid_enabled?
      permitted_user_params << :display_orcid_id_on_profile
    end

    if @user.is_enterprise_managed?
      permitted_user_params -= User::EnterpriseManagedDependency::ENTERPRISE_MANAGED_ATTRIBUTES
    end

    # Update user/profile params
    update_params = user_params.permit(permitted_user_params)
    @user.update(update_params) if @user.errors.none?

    if private_contribs.present?
      profile_settings = @user.profile_settings
      profile_settings.show_private_contribution_count = private_contribs
    end

    if user_feature_enabled?(:private_profile_setting) && private_profile.present?
      @user.update!(private_profile: private_profile)
    end

    if enable_pro_badge.present? && @user.can_have_pro_badge?
      profile_settings = @user.profile_settings
      profile_settings.pro_badge_enabled = enable_pro_badge
    end

    if @user.errors.any?
      # If this was for an inline edit, render error via JSON
      if request.xhr?
        return render json: { message: @user.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      flash[:error] = @user.errors.full_messages.to_sentence

      if params[:user][:profile_bio]
        redirect_to settings_user_profile_path
      else
        redirect_to settings_account_preferences_path
      end
    else
      # If this was for an inline edit, render the details partial
      if request.xhr?
        layout_data = Profiles::User::LayoutData.preload(profile_user: @user, viewer: current_user, active_tab: nil)
        return render Profiles::User::SidebarComponent.new(profile_layout_data: layout_data, gists_profile: false), layout: false
      end

      if profile_params_present?(params, private_profile, private_contribs)
        flash[:notice] = "Profile updated successfully"
        if params[:return_to] == "profile"
          redirect_to user_path(@user)
        else
          flash[:profile_updated] = true
          redirect_to settings_user_profile_path
        end
      else
        flash[:notice] = "Account updated successfully"
        if params[:return_to] == "back"
          redirect_to :back
        else
          redirect_to settings_account_preferences_path
        end
      end
    end
  end

  # Inline validation check
  def password_check # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        user = if logged_in?
          User.find(current_user.id)
        else
          User.new
        end

        user.readonly!
        user.password = params[:value]

        # trigger validations, we only care about the password validation and
        # not e.g. login or any others.
        user.valid?

        return head :ok if user.errors[:password].empty?

        error_message = user.errors[:password].to_sentence
        render body: "Password #{error_message}", status: 422, content_type: "text/fragment+html"
      end
    end
  end

  def change_password # rubocop:todo GitHub/UseRestfulActions
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    @user = current_user
    user_params = params.require(:user)
    password_params = user_params.permit(:old_password, :password, :password_confirmation)

    @user.change_password(
      old_password: password_params[:old_password],
      password: password_params[:password],
      password_confirmation: password_params[:password_confirmation],
      from_device_id: current_device_id,
    )

    if @user.errors.any?
      if @user.provided_weak_password?
        flash[::CompromisedPassword::WEAK_PASSWORD_KEY] = true
      elsif @user.password_related_error?
        flash[:password_error] = @user.errors.full_messages.to_sentence
      else
        flash[:error] = @user.errors.full_messages.to_sentence
      end
    else
      # Log user out and back in.
      logout_user :password_changed

      # If the device is verified no updated is needed.
      # If the device is unverified, we shouldn't verify it
      login_user @user, sign_in_verification_method: :nil, client: :password_changed
      clear_weak_password_session_variable

      # Notify the user that their password changed.
      flash[:notice] = "Password changed successfully."
      GitHub.dogstats.increment("user", tags: [
        "action:update",
        "password_changed:true",
        "from_session_revocation:#{!!params[:session_revoked]}",
        "recent_security_checkup:#{@user.recently_took_action_on_security_checkup?}",
      ])
    end

    redirect_to settings_security_path
  end

  def destroy
    if current_user.managed_user_deletion_disabled?
      flash[:error] = "Account deletion is managed through the IdP."
      return redirect_to settings_account_preferences_path
    end

    unless current_user.permit_deletion?(current_user)
      flash[:error] = "Cannot delete account. Please contact support."
      return redirect_to settings_account_preferences_path
    end

    unless account_deletion_phrase_verified? params[:confirmation_phrase]
      flash[:error] = "The confirmation phrase didn’t match. Please enter it again."
      return redirect_to settings_account_preferences_path
    end

    ReservedLogin.configure_tombstone_grace_period(current_user.display_login, persistent_client_id)
    current_user.instrument :destroy

    # Log out user before initiating deletion to ensure the current user_session is revoked prior to deletion. This is
    # important to ensuring the correctness of authnd's replication flow via Maxwell, where user_session DELETEs are
    # ignored but UPDATEs are not.
    user_to_delete = current_user
    logout_user :account_destroy
    user_to_delete.async_destroy

    if request.xhr?
      head 200
    else
      notice = if GitHub.flipper[:delay_user_deletion_for_spam_checks].enabled?(user_to_delete)
        "Account successfully deleted. Please note that it may take a few minutes for your profile to be deleted."
      else
        "Account successfully deleted."
      end
      redirect_to "/", notice: notice
    end
  end

  # Inline validation check for changing the "username" (aka login) for a logged in user
  def rename_check # rubocop:todo GitHub/UseRestfulActions
    new_username = params[:value]
    Failbot.push(user: new_username)

    # grab an instance of the current user (mark it as readonly so that any changes in this check cannot be saved accidentally)
    user = User.find(current_user.id)
    user.readonly!

    # immediately check to make sure the username has changed from the current username
    if new_username == user.display_login
      user.errors.add(:login, "must be different")
    else
      # set the new username on the user so we can run model validations on it
      user.login = new_username
      # trigger validations - we only care about the login validation here (not password, email, or anything else)
      user.valid?
    end

    login_errors = user.errors[:login]
    respond_to do |format|
      format.html_fragment do
        if !login_errors.empty?
          if suggest_usernames?(login_errors: login_errors, suggest_usernames_param: params[:suggest_usernames])
            suggested_usernames = get_username_suggestions(base_username: user.display_login)
          end
          return render partial: "account/rename_login_errors", formats: :html, status: 422, locals: {
            error_message:  user.login_error_message,
            suggested_usernames: suggested_usernames,
            source: params[:source],
          }
        end

        render html: "#{user.display_login} is available."
      end
    end
  end

  def rename # rubocop:todo GitHub/UseRestfulActions
    GitHub.context.push({
      spamurai_form_signals: spamurai_form_signals,
    })

    @user = User.find_by!(id: current_user.id)

    if @user.rename(params[:login])
      render "account/rename"
    else
      error_message = @user.errors[:login].to_sentence
      flash[:error] = "Username #{error_message}"
      redirect_to settings_account_preferences_path
    end
  end

  def spammer # rubocop:todo GitHub/UseRestfulActions
    render "users/spammer"
  end

  def billing # rubocop:todo GitHub/UseRestfulActions
    redirect_to settings_user_billing_url
  end

  def organizations_info # rubocop:todo GitHub/UseRestfulActions
    organizations_with_access = current_user.organizations_info_sorted_hash
    installable_marketplace_apps = current_user.installable_marketplace_apps_hash
    respond_to do |format|
      format.html do
        render partial: "repositories/new/orgs_select_menu", locals: {
            organizations_info: organizations_with_access,
            installable_marketplace_apps: installable_marketplace_apps,
            owner: @new_repository_owner,
            custom_disabled_message: nil,
            current_user_owned_organization_ids: current_user_owned_organization_ids,
        }
      end
    end
  end

  def dismiss_notice # rubocop:todo GitHub/UseRestfulActions
    current_user.deactivate_notice(params[:notice_name])
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def dismiss_repository_notice # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_repository_notice(params[:notice_name],
                                           repository_id: params[:repository_id])
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def user_profile_menu # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "site/header/logged_in/user_menu", formats: :html
      end
    end
  end

  def render_user_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Site::Header::UserDrawerSidePanelComponent.new(
          load_everything: true,
          user_can_create_organizations: params[:user_can_create_organizations],
          repository: current_repository,
          memex_enabled: params[:memex_enabled],
          account_switcher_helper: account_switcher_helper,
          user: current_user), layout: false
      end
    end
  end

  def set_protocol # rubocop:todo GitHub/UseRestfulActions
    if current_user.set_protocol_preference(
        params[:protocol_type], params[:protocol_selector])
      current_user.save!
    end
    head :ok
  end

  def record_developer_tools_survey_popup_shown # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_notice("desktop_survey_popup")

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def set_private_contributions_preference # rubocop:todo GitHub/UseRestfulActions
    if GitHub.flipper[:private_profile_setting].enabled?(current_user)
      set_private_contributions_preference_and_private_profile
    else
      @user = current_user
      @selected_tab = params[:tab]
      value = params[:user][:show_private_contribution_count]
      profile_settings = @user.profile_settings
      profile_settings.show_private_contribution_count = value
      back_to_profile = params[:return_to] == "profile"
      flash_key = :notice
      flash_key = :contribution_graph_notice if back_to_profile

      if @user.errors.any?
        flash[:error] = @user.errors.full_messages.to_sentence
      else
        if params[:user][:show_private_contribution_count] == "1"
          flash[flash_key] = PUBLIC_PRIVATE_CONTRIBUTION_SETTING_FLASH
        else
          flash[flash_key] = PUBLIC_CONTRIBUTION_SETTING_FLASH
        end
      end

      if back_to_profile
        redirect_to user_path(@user)
      else
        redirect_to settings_user_profile_path
      end
    end
  end

  private

  helper_method :this_user

  # Private: check if profile params are present before setting flash message
  def profile_params_present?(params, private_profile, private_contribs)
    params[:user][:profile_bio] ||
    params[:user][:profile_hireable] ||
    params[:user][:profile_display_staff_badge] ||
    params[:user][:profile_spoken_language_preference_code] ||
    private_contribs.present? ||
    private_profile.present?
  end

  # Ensure the user specified via the login in the URL is a real User.
  def ensure_user_exists
    unless this_user
      if request.xhr?
        head :not_found
      else
        render_404
      end
    end
  end

  # Private: Ensure `this_user` is not an organization.
  def ensure_not_organization
    return unless this_user

    head :not_acceptable if this_user.organization?
  end

  # Public: Should the 'Activity overview' section be shown on this user's profile?
  def activity_overview_enabled?
    profile_settings = this_user.profile_settings
    profile_settings.activity_overview_enabled?
  end

  memoize def this_user
    if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      User.find_by_login(params[:user_id])
    end
  end

  def account_deletion_phrase_verified?(phrase)
    return false if phrase.blank?
    User.account_deletion_phrase.downcase == phrase.strip.downcase
  end

  def ensure_trade_screening_status_allows_deletion
    return unless logged_in?

    can_proceed = current_user.perform_live_sdn_screening
    # a spammy user is allowed to delete their account
    if can_proceed || current_user.trade_screening_status == "spammy"
      return
    end
    flash[current_user.trade_screening_status_notice] = true
    redirect_to settings_account_preferences_path
  end

  def ensure_valid_email
    return unless params[:user] && params[:user][:profile_email].present?
    valid_emails = current_user.possible_profile_emails
    # Ideally we wouldn't allow the existing profile email unless it was
    # verified. But, changing that behavior would probably surprise/confuse
    # existing users. But, this does prevent a bad actor from purposefully
    # adding a new arbitrary profile email address going forward.
    valid_emails << current_user.profile_email
    render_404 unless valid_emails.include?(params[:user][:profile_email])
  end

  def users_rate_limit_filter
    # if the update action includes an old password param, rate limit it
    if UPDATE_ACTIONS.include?(params[:action])
      return false unless params[:user]
      return params[:user][:old_password].present?
    end

    # always rate limit rename check actions
    if RENAME_CHECK_ACTIONS.include?(params[:action])
      return true
    end

    # always rate limit change password actions
    if CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      return true
    end

    # always rate limit rename actions
    if RENAME_ACTIONS.include?(params[:action])
      true
    end
  end

  def users_rate_limit_key
    if UPDATE_ACTIONS.include?(params[:action])
      "users_update_limiter:#{current_user.id}"
    elsif RENAME_CHECK_ACTIONS.include?(params[:action])
      "users_controller.rename_check:#{current_user.id}"
    elsif CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      "users_controller.change_password:#{current_user.id}"
    elsif RENAME_ACTIONS.include?(params[:action])
      "users_controller.rename:#{current_user.id}"
    end
  end

  def users_rate_limit_log_key
    if UPDATE_ACTIONS.include?(params[:action])
      "update-user-#{current_user.id}"
    elsif RENAME_CHECK_ACTIONS.include?(params[:action])
      "rename_check-user-#{current_user.id}"
    elsif CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      "change-password-user-#{current_user.id}"
    elsif RENAME_ACTIONS.include?(params[:action])
      "rename-user-#{current_user.id}"
    end
  end

  def users_rate_limit_max
    if UPDATE_ACTIONS.include?(params[:action])
      60
    elsif RENAME_CHECK_ACTIONS.include?(params[:action])
      100
    elsif CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      60
    elsif RENAME_ACTIONS.include?(params[:action])
      10
    end
  end

  def users_rate_limit_ttl
    if UPDATE_ACTIONS.include?(params[:action])
      1.day
    elsif RENAME_CHECK_ACTIONS.include?(params[:action])
      GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL
    elsif CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      1.day
    elsif RENAME_ACTIONS.include?(params[:action])
      1.hour
    end
  end

  def users_rate_limit_record
    if UPDATE_ACTIONS.include?(params[:action])
      GitHub.dogstats.increment("rate_limited", tags: ["action:user_update"])
    elsif RENAME_CHECK_ACTIONS.include?(params[:action])
      GitHub.dogstats.increment("rate_limited", tags: ["action:rename_check"])
    elsif CHANGE_PASSWORD_ACTIONS.include?(params[:action])
      GitHub.dogstats.increment("rate_limited", tags: ["action:change_password"])
    elsif RENAME_ACTIONS.include?(params[:action])
      GitHub.dogstats.increment("rate_limited", tags: ["action:rename"])
    end
  end

  def from_settings_page?(pathname)
    request.referrer.present? && URI(request.referrer).path == pathname
  end

  def target_for_conditional_access
    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless this_user.present?
    this_user
  end

  # this is the standard way to opt-out of a CAP policy, it is not a new action in this Controller
  def tenant_verification_enforceable # rubocop:todo GitHub/UseRestfulActions
    return :no if action_name == "password_check"
    :yes
  end

  def find_new_repository_owner
    owner_id = params.fetch(:owner_id, nil).to_s
    @new_repository_owner = if owner_id.blank?
      Repositories::New::OwnerEmptySelectionOption.new
    elsif owner_id == current_user.id.to_s
      current_user
    else
      # will raise an exception if the owner_id param doesn't point to
      # an Organization that current_user belongs to
      current_user.organizations.find(owner_id)
    end
  end

  def ensure_user_is_a_user
    render_404 unless this_user.user?
  end

  def ensure_user_not_hidden_from_viewer
    render_404 if this_user.hide_from_user?(current_user)
  end

  def delete_sponsorship_rollback_notice
    select_write_database { current_user&.delete_notice(:sponsorship_rollback) }
  end

  def set_private_contributions_preference_and_private_profile
    @user = current_user
    @selected_tab = params[:tab]
    profile_settings = @user.profile_settings
    private_contribution_param = ActiveRecord::Type::Boolean.new.cast(
      params[:user][:show_private_contribution_count]
    )

    if profile_settings.show_private_contribution_count != private_contribution_param
      profile_settings.show_private_contribution_count = private_contribution_param
      if @user.errors.any?
        flash[:error] = @user.errors.full_messages.to_sentence
      else
        back_to_profile = params[:return_to] == "profile"
        flash_key = :notice
        flash_key = :contribution_graph_notice if back_to_profile
        flash[flash_key] = if private_contribution_param == true
          PUBLIC_PRIVATE_CONTRIBUTION_SETTING_FLASH
        else
          PUBLIC_CONTRIBUTION_SETTING_FLASH
        end
      end
    end
    private_profile_param = ActiveRecord::Type::Boolean.new.cast(
      params[:user][:private_profile]
    )

    if !private_profile_param.nil? && @user.private_profile != private_profile_param
      @user.update!(private_profile: private_profile_param)
      if @user.errors.any?
        flash[:error] = + @user.errors.full_messages.to_sentence
      else
        flash[:notice] = flash[:notice].to_s + (
          if private_profile_param == true
            "Your profile is now private."
          else
            "Your profile is now public."
          end
        )
      end
    end

    if params[:return_to]
      redirect_to user_path(@user)
    else
      redirect_to settings_user_profile_path
    end
  end

  memoize def current_user_owned_organization_ids
    if GitHub.create_repo_perf?
      current_user.owned_organization_ids
    else
      []
    end
  end
end
