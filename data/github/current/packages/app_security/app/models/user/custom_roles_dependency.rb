# typed: false
# frozen_string_literal: true

module User::CustomRolesDependency
  # Public: This checks if the user is an org and has a plan that supports custom repository roles
  #
  # Returns a Boolean
  def custom_roles_supported?
    organization? && plan_supports?(:custom_roles)
  end
end
