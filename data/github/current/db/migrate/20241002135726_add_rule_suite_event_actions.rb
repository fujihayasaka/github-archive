# typed: true
# frozen_string_literal: true
class AddRuleSuiteEventActions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def up
    change_table(:repository_rule_suites, bulk: true) do |t|
      t.change :ref_name, "varbinary(1024)", null: true, default: nil
      add_column :repository_rule_suites, :event_action_id, :bigint, unsigned: true, null: true, default: nil
      add_column :repository_rule_suites, :event_action_type, "varchar(64)", null: true, default: nil
      t.index [:event_action_id, :event_action_type], name: :index_repository_rule_suites_event_action_id_and_type
    end
  end

  def down
    change_table(:repository_rule_suites, bulk: true) do |t|
      t.change :ref_name, "varbinary(1024)", null: false
      t.drop_column :repository_rule_suites, :event_action_id
      t.drop_column :repository_rule_suites, :event_action_type
      t.remvoe_index [:event_action_id, :event_action_type], name: :index_repository_rule_suites_event_action_id_and_type
    end
  end
end
