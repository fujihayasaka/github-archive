# typed: true
# frozen_string_literal: true

# An email belonging to a user account on an Enterprise Server installation.
class EnterpriseInstallationUserAccountEmail < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification

  belongs_to :enterprise_installation_user_account

  validates :enterprise_installation_user_account, presence: true
  validates :email,
    presence: true,
    uniqueness: {
      scope: :enterprise_installation_user_account_id,
      case_sensitive: false,
      message: "already exists on this account",
    },
    length: { in: 3..100 },
    format: { with: User::EMAIL_REGEX, message: "does not look like an email address" }

  scope :primary, -> { where(primary: true) }
  after_create :update_business_license_usage

  def platform_type_name
    "EnterpriseServerUserAccountEmail"
  end

  def target_for_conditional_access
    T.must(enterprise_installation_user_account).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_enterprise_installation_user_account.then(&:async_target_for_conditional_access)
  end

  def update_business_license_usage
    T.must(enterprise_installation_user_account).update_business_license_usage
  end
end
