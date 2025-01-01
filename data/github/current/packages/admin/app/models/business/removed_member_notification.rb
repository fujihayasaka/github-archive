# typed: true
# frozen_string_literal: true

# Stores members removed from Business due to 2FA enforcement.
# Expires in 90 days.
#
# Note: Only one notification per business/user combination can exist. A user cannot
# be notified of removal for both reasons at once.
class Business::RemovedMemberNotification
  TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE = "two_factor_requirement_non_compliance".freeze

  attr_reader :business, :user

  def initialize(business, user)
    @business = business
    @user = user
  end

  # Public: Dismiss the current notification
  #
  # Returns a boolean (true if the arguments were valid,
  # false if any were invalid)
  def dismiss
    return false unless valid_argument_types?
    GitHub.kv.del(business_user_key) # rubocop:todo GitHub/DoNotUseGlobalKv
    true
  end

  def add_two_factor_requirement_non_compliance
    add(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
  end

  def two_factor_requirement_non_compliance?
    exists?(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
  end

  def any?
    stored_value.present?
  end

  private

  def add(reason:)
    return false unless valid_argument_types?(reason: reason)
    GitHub.kv.set(business_user_key, reason.to_s, expires: 90.days.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def exists?(reason:)
    return false unless valid_argument_types?(reason: reason)
    stored_value == reason
  end

  def stored_value
    GitHub.kv.get(business_user_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def business_user_key
    "business-membership-removed.#{business.id}:#{user.id}"
  end

  def valid_argument_types?(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
    business.is_a?(Business) &&
      user.is_a?(User) &&
      reason == TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE
  end
end
