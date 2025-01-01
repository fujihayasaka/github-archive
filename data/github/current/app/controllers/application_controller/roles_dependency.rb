# typed: false
# frozen_string_literal: true

module ApplicationController::RolesDependency
  extend ActiveSupport::Concern

  included do
    helper_method :site_admin?, :biztools_user?, :employee?, :staff_assets?,
      :devtools_assets?, :preview_features?, :anonymous?,
      :can_toggle_site_admin_and_employee_status?,
      :site_admin_performance_stats_mode_enabled?, :all_users_are_employees?,
      :canary_cookie_enabled?, :staffbar_allowed?
  end

  # Returns true when the haproxy_backend cookie is present
  #
  # Returns a Boolean
  def canary_cookie_enabled?
    cookies[:haproxy_backend].present?
  end

  # Check if the current user is a site admin.
  # Site admins have access to administrative features.
  #
  # Returns true if the logged in user is an account that is flagged as staff
  def site_admin?
    logged_in? && current_user.site_admin?
  end

  # Check if the current user is a business tools user.
  # These users have access to business-specific dotcom administrative features.
  #
  # Returns a Boolean
  def biztools_user?
    logged_in? && (current_user.biztools_user? || current_user.site_admin?)
  end

  # Check if the current user is a GitHub developer. These users have access to
  # devtools, but not stafftools.
  #
  # Returns boolean.
  def github_developer?
    logged_in? && current_user.github_developer?
  end

  # Check if the user is an employee of GitHub, inc.
  #
  # Returns true if the logged in user is on the @github/employees team.
  def employee?
    all_users_are_employees? || (logged_in? && current_user.employee?)
  end

  # Check if the user has any access to administrative functionality.
  #
  # Returns true if the logged in user has at least one role that grants them
  # access to administrative functionality.
  def admin_frontend_accessible?
    site_admin? || biztools_user? || github_developer?
  end

  # Check if the "real user" is staff
  # This goes if the current user is staff *or* if it's an impersonated session
  # (a staff member fake-signed-in as someone else)
  def real_user_site_admin?
    site_admin? || session_impersonated?
  end

  # Check if we should load staff assets. We need to
  # load them for staff but also for impersonation
  # for the staff performance bar
  def staff_assets?
    can_toggle_site_admin_and_employee_status? || github_developer? || session_impersonated?
  end

  def devtools_assets?
    staff_assets? && GitHub.devtools_enabled?
  end

  # Check if we should show the staff performance bar to the user.
  def staffbar_allowed?
    staff_assets? && !(session_impersonated? && GitHub.enterprise?)
  end

  # Returns true if this environment is protected by a VPN or isolated in such
  # a manner that all users are employees.
  # Can be used to grant employees access to certain routes in environments
  # that do not have a User record for employees, like test or staging
  # environments.
  def all_users_are_employees?
    !!ENV["ALL_USERS_ARE_EMPLOYEES"]
  end

  # Check if current user can access site reliabilty graphs
  def site_graph_allowed?
    site_admin? || employee? || user_disabled_site_admin_or_employee_status?
  end

  # before_action to restrict access to site reliability graphs
  #
  # Throws a 404 if current user is not permitted to look at the graphs
  def site_graph_only
    render_404 unless site_graph_allowed?
  end

  # before_action to restrict access to site admin members only
  #
  # Throws a 404 if the current user is not site admin.
  def site_admin_only
    return if site_admin?
    redirect_jit_for_employees
  end

  # before_action to restrict access to business tools users
  #
  # Throws a 404 if the current user is not a business tools user
  def biztools_only
    return if biztools_user?
    redirect_jit_for_employees
  end

  # Show a special 403 error page to employees that don't have access to an
  # internal page.  Renders a 404 page if the user isn't an employee.
  def render_403_for_employees
    if employee?
      render file: "#{Rails.root}/public/403-hubber.html", layout: false,
             status: 403, formats: [:html]
    else
      render_404
    end
  end

  # Redirects to JIT if the user is an employee and don't have access to an
  # internal page.
  # Renders a 404 page if the user isn't an employee.
  def redirect_jit_for_employees
    if employee?
      # Redirects user to JIT into stafftools to get site_admin.
      # If the user is not authorized, jit-okta-bouncer will display an error message
      # and instructions on how to get access.
      redirect_query_params = { redirect: request.original_url }.to_query
      redirect_to "https://jit-okta-bouncer.githubapp.com/stafftools?#{redirect_query_params}"
    else
      render_404
    end
  end

  # before_action to restrict access to employees only.
  #
  # Throws a 404 if the current user is not a member of @github/employees.
  def employee_only
    render_404 unless employee?
  end

  # Public: Check if user is actually a site admin or employee that can
  # temporarily toggle their role.
  #
  # Returns a Boolean.
  def can_toggle_site_admin_and_employee_status?
    return unless logged_in?
    site_admin? || employee? || user_disabled_site_admin_or_employee_status?
  end

  # The user is actually a site admin or GitHub employee, but they have disabled
  # their powers.
  #
  # Returns boolean.
  def user_disabled_site_admin_or_employee_status?
    @user_disabled_site_admin || @user_disabled_employee_status
  end

  # Public: Disable staff mode for session so user can see the whole as
  # our everyday users.
  #
  # Returns nothing.
  def disable_site_admin_and_employee_mode
    session[:disable_site_admin_and_employee_status] = true
  end

  # Public: Enables normal staff after temporarily disabling it.
  #
  # Returns nothing.
  def enable_site_admin_and_employee_mode
    session.delete(:disable_site_admin_and_employee_status)
  end

  def toggle_site_admin_and_employee_mode
    if site_admin? || employee?
      disable_site_admin_and_employee_mode
    else
      enable_site_admin_and_employee_mode
    end
  end

  # Public: Disable performance stats in the staff bar so pages load faster.
  #
  # Returns nothing.
  def disable_site_admin_performance_stats_mode
    session.delete(:enable_site_admin_performance_stats)
  end

  # Public: Enables performance stats in the staff bar. This adds significant
  # time to page loads for staff.
  #
  # Returns nothing.
  def enable_site_admin_performance_stats_mode
    session[:enable_site_admin_performance_stats] = true
  end

  def site_admin_performance_stats_mode_enabled?
    !!session[:enable_site_admin_performance_stats]
  end

  # Check if the current user can preview staff-only features.
  #
  # Returns a Boolean.
  def preview_features?
    logged_in? && current_user.preview_features?
  end

  # before_action to restrict access to members who can preview features.
  #
  # Throws a 404 if the current user isn't allowed to preview features.
  def preview_features_only
    render_404 if !preview_features?
  end

  def anonymous?
    !logged_in?
  end

  # Staff/employee pretend to be normal when mission control is hidden.
  def set_site_admin_and_employee_status
    if logged_in? && session && session[:disable_site_admin_and_employee_status]
      if site_admin?
        current_user.site_admin = false
        @user_disabled_site_admin = true
      end

      if employee?
        current_user.disable_employee_mode
        @user_disabled_employee_status = true
      end
    end
  end
end
