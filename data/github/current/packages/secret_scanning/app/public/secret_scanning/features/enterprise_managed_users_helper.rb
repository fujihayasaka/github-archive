# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::EnterpriseManagedUsersHelper
  sig { params(user: User).returns(T::nilable(Business)) }
  def get_business_for_user(user)
    return GitHub.global_business if GitHub.single_business_environment?
    return nil unless user.is_enterprise_managed?
    user.enterprise_managed_business
  end
end
