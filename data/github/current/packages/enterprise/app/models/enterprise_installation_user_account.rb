# typed: true
# frozen_string_literal: true

# A user account on an Enterprise Server installation.
#
# Belongs to a single Enterprise Server installation.
# Has possibly many associated emails, each represented by
# EnterpriseInstallationUserAccountEmail.
# Belongs to a single BusinessUserAccount.
class EnterpriseInstallationUserAccount < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  belongs_to :enterprise_installation
  belongs_to :business_user_account

  has_many :emails, dependent: :delete_all, class_name: "EnterpriseInstallationUserAccountEmail"

  validates :enterprise_installation, presence: true
  validates :remote_user_id,
    presence: true,
    uniqueness: { scope: :enterprise_installation_id, message: "already exists on this installation" }
  validates :remote_created_at, presence: true
  validates :login, presence: true, length: { in: 1..255 }, unicode3: true
  validates :profile_name, length: { maximum: 255 }

  # destroy callbacks are not called for records deleted from
  # `EnterpriseInstallationUserAccountsImporter#delete_missing_accounts`
  after_commit :cleanup_business_user_account, on: :destroy
  after_commit :update_business_license_usage

  def platform_type_name
    "EnterpriseServerUserAccount"
  end

  def target_for_conditional_access
    T.must(enterprise_installation).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_enterprise_installation.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def update_business_license_usage
    business_user_account&.update_business_license_usage
  end

  private

  def cleanup_business_user_account
    return unless business_user_account.present?
    return if T.must(business_user_account).user_id.present?
    return if T.must(business_user_account).enterprise_installation_user_accounts.where.not(id: self.id).exists?
    T.must(business_user_account).destroy
  end
end
