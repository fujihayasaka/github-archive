# typed: strict
# frozen_string_literal: true

module Business::CustomRolesDependency
  extend T::Helpers

  requires_ancestor { Business }

  # Public: returns the custom roles for the enterprise
  sig { returns(ActiveRecord::Relation) }
  def custom_enterprise_roles
    EnterpriseRole.custom_roles_for_enterprise(self)
  end

  alias_method :roles_assignable_to_target, :custom_enterprise_roles
end
