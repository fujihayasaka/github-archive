# typed: true
# frozen_string_literal: true

class Businesses::Admins::ListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :admins

  def admin_infos
    admins.each_with_object([]) do |admin, admins_info|
      admins_info.append({
        user: admin,
        business_user_account: business_user_account_for(admin),
        role: business.role_for(admin),
      })
    end
  end

  def admins_count
    admins.count
  end

  def member_link(admin_info)
    member = admin_info[:user]
    business_user_account = admin_info[:business_user_account]

    return urls.user_path(member) if business_user_account.nil?
    # If business_user_account is present, just link to its user - don't need to worry about
    # server-only members, since an Enterprise admin has to be a cloud user
    urls.enterprise_person_organizations_enterprise_path(business_user_account.business,
                                                         business_user_account.user)
  end

  private

  def business_user_account_for(admin)
    business_user_accounts.find { |user_account| user_account.user == admin }
  end

  def business_user_accounts
    @business_user_accounts ||= BusinessUserAccount.where(user_id: admin_ids, business: business).includes(:user)
  end

  def admin_ids
    @admin_ids ||= admins.pluck(:id)
  end
end
