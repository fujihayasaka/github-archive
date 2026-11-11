# typed: true

class WidenGateApproversApproverTypeColumn < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE gate_approvers
        MODIFY COLUMN `approver_type` varchar(12) NOT NULL COMMENT 'the polymorphic approver type (User, Team, or BusinessTeam)';
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Cannot safely shrink approver_type back to varchar(4) — existing BusinessTeam rows would be truncated"
  end
end
