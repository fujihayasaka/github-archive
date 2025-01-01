# typed: true
# frozen_string_literal: true

class Stafftools::SessionsController < StafftoolsController
  before_action :require_admin_frontend, except: :back_to_the_login
  before_action :site_admin_only, except: :back_to_the_login
  before_action :ensure_reason, only: [:impersonate, :override_impersonate]
  before_action :ensure_impersonated_user_is_not_site_admin, only: [:impersonate, :override_impersonate]
  before_action :ensure_active_staff_access_grant, only: [:impersonate]

  skip_before_action :ensure_stafftools_authorization, only: [:back_to_the_login] unless GitHub.enterprise?

  def impersonate # rubocop:todo GitHub/UseRestfulActions
    instrument("staff.fake_login", user: impersonated_user, note: impersonation_reason)
    impersonated_login_user impersonated_user, impersonation_reason
    redirect_to "/"
  end

  # For impersonating users without a staff access grant.
  # Requires "can-impersonate-users-without-permission" stafftools role.
  def override_impersonate # rubocop:todo GitHub/UseRestfulActions
    instrument("staff.override_fake_login", user: impersonated_user, note: impersonation_reason)
    impersonated_login_user impersonated_user, impersonation_reason
    redirect_to "/"
  end

  # Hitting this URL after using impersonate will restore your previous session.
  def back_to_the_login # rubocop:todo GitHub/UseRestfulActions
    impersonated_user = self.current_user
    former_user = impersonated_logout_user

    redirect_to stafftools_user_url(impersonated_user)

    instrument("staff.exit_fake_login", user: impersonated_user)
  end

  private

  def impersonated_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @impersonsated_user ||= User.find_by_login(params[:id])
  end

  def current_access_grant # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @current_access_grant ||= impersonated_user.active_staff_access_grant
  end

  def impersonation_reason # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @impersonation_reason ||= current_access_grant&.reason || reason_with_notes
  end

  def reason_with_notes
    params[:notes].present? ? params[:reason].concat(": ", params[:notes]) : params[:reason]
  end

  def ensure_impersonated_user_is_not_site_admin
    if impersonated_user.site_admin?
      flash[:error] = "You cannot impersonate a site admin"
      redirect_to :back
    end
  end

  def ensure_reason
    if impersonation_reason.blank?
      flash[:error] = "You must provide a reason for the log"
      redirect_to :back
    end
  end

  def ensure_active_staff_access_grant
    if current_user.access_grant_required_for_user_impersonation? && current_access_grant.nil?
      flash[:error] = "There is no active grant!"
      redirect_to :back
    end
  end
end
