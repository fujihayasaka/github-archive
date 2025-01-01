# typed: true
# frozen_string_literal: true

class DropUserRolesFromIamAbilities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IamAbilities)

  def change
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    drop_table :user_roles
  end
end
