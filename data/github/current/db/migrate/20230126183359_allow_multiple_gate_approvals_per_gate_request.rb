# typed: true
class AllowMultipleGateApprovalsPerGateRequest < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :gate_approvals, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :gate_request_id, :bigint, unsigned: true, null: false
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :approver_id, :bigint, unsigned: true, null: false
      t.change :user_id, :bigint, unsigned: true, null: false
      t.change :gate_approval_log_id, :bigint, unsigned: true, null: true
      t.change :environment_id, :bigint, unsigned: true, null: false

      t.remove_index name: "index_gate_approvals_on_gate_request_id_and_user_id"
      t.index [:gate_request_id, :user_id], unique: false
    end
  end

  def down
    change_table :gate_approvals, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :gate_request_id, :int, null: false
      t.change :repository_id, :int, null: false
      t.change :approver_id, :int, null: false
      t.change :user_id, :int, null: false
      t.change :gate_approval_log_id, :int, null: true
      t.change :environment_id, :int, null: false

      t.remove_index name: "index_gate_approvals_on_gate_request_id_and_user_id"
      t.index [:gate_request_id, :user_id], unique: true
    end
  end
end
