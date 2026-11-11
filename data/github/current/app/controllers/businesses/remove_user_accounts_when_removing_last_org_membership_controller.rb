# typed: true
# frozen_string_literal: true

class Businesses::RemoveUserAccountsWhenRemovingLastOrgMembershipController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    setting_value = params[:remove_user_accounts_when_removing_last_org_membership]&.to_s
    remove_existing = params[:remove_existing_unaffiliated_users] == "true"

    message = case setting_value
    when "true"
      this_business.enable_remove_user_accounts_when_removing_last_org_membership(actor: current_user)

      if remove_existing
        synchronizer = BusinessUserAccount::SynchronizeAccounts.new(business: this_business, actor: current_user)
        orchestration = synchronizer.remove_unaffiliated_accounts

        if orchestration.skipped?
          "Users will be removed from the enterprise when removed from all organizations."
        else
          "Removing unaffiliated users from the enterprise. This will take a few minutes."
        end
      else
        "Users will be removed from the enterprise when removed from all organizations."
      end
    when "false"
      this_business.disable_remove_user_accounts_when_removing_last_org_membership(actor: current_user)
      "Users will stay in the enterprise as unaffiliated users when removed from all organizations."
    else
      "Invalid setting value."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end
end
