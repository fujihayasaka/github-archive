# typed: true

# rubocop:disable GitHub/OneTablePerMigration
class DropActionsEnvironmentsTablesInRepositoriesCluster < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    drop_table :environments
    drop_table :gate_approval_logs
    drop_table :gate_approvals
    drop_table :gate_approvers
    drop_table :gate_branch_policies
    drop_table :gate_requests
    drop_table :gates
    drop_table :pinned_environments
    drop_table :repository_tech_project_stacks
    drop_table :repository_tech_projects
  end
end
