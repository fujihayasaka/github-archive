# typed: true
# frozen_string_literal: true

class EnterpriseInstallationLicenseAttributer
  def initialize(installation_ids)
    @installation_ids = installation_ids
  end

  def user_ids
    @user_ids ||= enterprise_installation_user_accounts.
      where.not(business_user_accounts: { user_id: nil }).
      pluck("business_user_accounts.user_id").
      to_set
  end

  def emails
    @emails ||= enterprise_installation_user_accounts_without_users.
      joins(:emails).
      merge(EnterpriseInstallationUserAccountEmail.primary).
      group(:id).
      pluck("MIN(enterprise_installation_user_account_emails.email)").
      map(&:downcase).
      to_set
  end

  def unidentified_business_user_account_ids
    @unidentified_business_user_account_ids ||= enterprise_installation_user_accounts_without_users.
      where.not(id: EnterpriseInstallationUserAccountEmail.primary.select(:enterprise_installation_user_account_id)).
      pluck(:business_user_account_id).
      to_set
  end

  def unique_count
    user_ids.count + emails.count + unidentified_business_user_account_ids.count
  end

  private

  attr_reader :installation_ids

  def enterprise_installation_user_accounts
    EnterpriseInstallationUserAccount.
      joins(:business_user_account).
      where(enterprise_installation_id: installation_ids)
  end

  def enterprise_installation_user_accounts_without_users
    enterprise_installation_user_accounts.
      where(business_user_accounts: { user_id: nil })
  end
end
