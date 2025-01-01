# typed: true
# frozen_string_literal: true

class BillingManagers::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization

  def current_or_pending_billing_managers?
    org_billing_managers.any? || org_billing_manager_invitations.any?
  end

  def show_remove_user_completely?(user)
    organization_admin?(current_user) && organization.direct_or_team_member?(user) && (user != current_user)
  end

  def user_path(user)
    if organization_admin?(current_user)
      urls.org_person_path(organization, user)
    else
      urls.user_path(user)
    end
  end

  def dialog_warning_message(user)
    if user == current_user
      if organization_admin?(user)
        "As an owner of the #{organization.safe_profile_name} organization, you’ll still be able to update billing and payment settings, but you will no longer receive its billing related email."
      else
        "You will no longer be able to see #{organization.safe_profile_name}’s billing page, perform any billing related actions, or receive its billing related email."
      end
    else
      if organization_admin?(user)
        "As an owner of the #{organization.safe_profile_name} organization, #{user.display_login} will still be able to update billing and payment settings, but will no longer receive its billing related email."
      elsif user.has_trade_screening_record_linked_to_org?(organization: organization)
        TradeControls::Notices.org_member_linked_billing_info_warning
      else
        "This user will no longer be able to see #{organization.safe_profile_name}’s billing page, or perform any billing related actions."
      end
    end
  end

  def org_billing_managers
    @billing_managers ||= organization.billing_managers
  end

  def org_billing_manager_invitations
    @billing_manager_invitations ||= organization.pending_invitations.with_business_role(:billing_manager)
  end

  private

  def organization_admins
    @admins ||= organization.admins
  end

  def organization_admin?(user)
    organization_admins.include?(user)
  end
end
