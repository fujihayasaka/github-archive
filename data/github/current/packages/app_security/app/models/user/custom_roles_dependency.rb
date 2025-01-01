# typed: strict
# frozen_string_literal: true

module User::CustomRolesDependency
  extend T::Helpers

  requires_ancestor { User }

  # Public: This checks if the user is an org and has a plan that supports custom repository roles
  sig { returns(T::Boolean) }
  def custom_roles_supported?
    T.cast(organization?, T::Boolean) && plan_supports?(:custom_roles)
  end
end
