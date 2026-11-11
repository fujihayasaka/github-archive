# typed: false
# frozen_string_literal: true

class Gists::ApplicationController < ::ApplicationController
  include GistsHelper

  layout "layouts/gists"

  # we need to execute CAP checks after we ensure that the current_user
  # is the same user logged in via GitHub. This is so that we can return
  # the appropriate future owner of a Gist for creation endpoints.
  # needs investigation for protected organization access
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :auto_oauth
  before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  skip_after_action :set_login_cookie

  # by default, gists controller actions do not check for the two factor requirement interrupt
  skip_before_action :account_2fa_requirement_interrupt

  helper_method :gist_login_url, :gist_logout_url, :current_commit, :completed_gist_signup_flow?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:not_found]

  # Route handler for all routes not handled by Gist
  # (aka dotcom routes)
  def not_found # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  # Is this a request for the gist application?
  def gist_request? # rubocop:todo GitHub/UseRestfulActions
    true
  end

  private

  def resource_for_conditional_access
    # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    return :no_resource_for_conditional_access unless this_gist
    # rubocop:enable GitHub/SpecifyResourceForConditionalAccess
    this_gist
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_gist # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_gist.target_for_conditional_access
  end

  # Gists are disabled on Proxima so no need to run policy (which will cause test failures)
  def tenant_verification_enforceable
    :no
  end

  def two_factor_enforceable
    :no
  end

  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def this_gist # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_gist if defined? @this_gist
    @this_gist = Gist.active.with_name_with_owner(params[:user_id], params[:gist_id])
  end

  def this_gist!
    return render_404 if this_gist.nil?
    this_gist
  end

  # This is a workaround for one of our god objects, current_commit which
  # is used in PreviewableCommentFormComponent and
  # for editor_config
  def current_commit
  end

  # Keeps Gist session in sync with GitHub by looking at shared cookies. Handles these scenarios:
  #
  # If user has logged in to github but not gist, automatically run user through oauth flow.
  # If user has logged in as different user on GitHub, run back through oauth flow.
  def auto_oauth
    return unless GitHub.gist3_domain? && request.get?
    user_cookie = cookies["dotcom_user"]

    if logged_in? && user_cookie.present? && user_cookie != current_user.login
      # Logged into GitHub as a different user
      user_session_cookies_delete
      redirect_to_login(request.original_url)
    elsif !logged_in? && user_cookie.present?
      # Logged into GitHub but not Gist
      redirect_to_login(request.original_url)
    end
  end

  def redirect_to_login(return_to = nil)
    url_options = return_to ? { return_to: return_to } : {}

    redirect_to gist_login_url(url_options)
  end

  def gist_login_url(*args)
    if GitHub.gist3_domain?
      gist_oauth_login_url(*args)
    else
      login_url(*args)
    end
  end

  def gist_logout_url(*args)
    if GitHub.gist3_domain?
      gist_oauth_logout_url(*args)
    else
      GitHub.auth.logout_url
    end
  end

  # Internal: Extends `initialize_log_data` provided by ApplicationController
  # to add a key for filtering Gist requests. We're overriding here instead of
  # adding another before_action since we want to make sure the key is set as
  # early as possible in case another filter or exception stops the request.
  def initialize_log_data
    super

    log_data.merge! gist: true
  end

  # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
  def initial_failbot_context
    return @initial_failbot_context if defined?(@initial_failbot_context)
    @initial_failbot_context = super
    @initial_failbot_context.merge!("gh.gist.repo_name" => this_gist&.repo_name)
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  # Public: Did this user just complete the signup flow? For us to consider this
  # a successful gist signup, two things need to be true:
  #
  # - signup=true is included in the URL. This is added to return_to in Gists/Users#new.
  # - The user must be logged in with an account created in the last 30 minutes.
  #
  # Returns true if we're confident that the user just completed a signup flow
  # initiated from Gist.
  def completed_gist_signup_flow? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @completed_signup if defined?(@completed_signup)

    returning_from_signup = params[:signup] == "true"
    current_user_is_new   = logged_in? && current_user.created_at > 30.minutes.ago
    signup_tracked        = session[:gist_signup_tracked]

    @completed_signup = (returning_from_signup && current_user_is_new && !signup_tracked).tap do |completed|
      session[:gist_signup_tracked] = true if completed
    end
  end

end
