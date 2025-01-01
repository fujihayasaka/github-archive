# typed: true
# frozen_string_literal: true

class Stafftools::Users::EmployeeAccessRevocationsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_user_revocable

  def create
    suspend_user_and_revoke_all_sessions!
    revoke_all_oauth_authorizations!(entry_point: :stafftools_users_employee_access_revocations_controller_create)
    unverify_all_public_keys!
    remove_github_org_affiliations!
    remove_all_special_hubber_priveleged_roles!
    clear_password!

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "All access for #{this_user} has been revoked.",
    )
  end

  private

  def ensure_user_revocable
    unless this_user.user? && this_user.employee? && GitHub.require_employee_for_site_admin?
      redirect_to(
        stafftools_user_administrative_tasks_path(this_user),
        flash: { error: "Access for #{this_user} cannot be revoked." },
      )
    end
  end

  def suspend_user_and_revoke_all_sessions!
    this_user.suspend(params[:reason], actor: current_user)
  end

  def revoke_all_oauth_authorizations!(entry_point:)
    this_user.oauth_authorizations.each do |oauth_authorization|
      oauth_authorization.destroy_with_explanation(:site_admin, entry_point: entry_point)
    end
  end

  def unverify_all_public_keys!
    this_user.public_keys.each do |public_key|
      public_key.unverify(:site_admin)
    end
  end

  def remove_github_org_affiliations!
    github_org = Organization.find_by_login("github")
    github_org.remove_any_affiliation(this_user, actor: current_user)
  end

  def remove_all_special_hubber_priveleged_roles!
    this_user.revoke_privileged_access(params[:reason])
  end

  def clear_password!
    this_user.set_random_password(actor: current_user)
  end
end
