# typed: strict
# frozen_string_literal: true

module Business::CustomRolesDependency
  extend T::Helpers

  requires_ancestor { Business }

  # Public: This checks if the business supports custom organization roles
  sig { returns(T::Boolean) }
  def custom_roles_supported?
    feature_enabled?(:enterprise_custom_organization_roles) && plan_supports?(:custom_roles)
  end
end
