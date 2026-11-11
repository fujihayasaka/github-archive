# typed: true
# frozen_string_literal: true

class RepositoriesPushesSha256EventActionRefUpdates < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :event_action_ref_updates, bulk: true do |t|
      t.change :before_oid, :string, limit: 64, null: true
      t.change :after_oid, :string, limit: 64, null: true
      t.change :policy_oid, :string, limit: 64, null: true
    end
  end

  def down
    change_table :event_action_ref_updates, bulk: true do |t|
      t.change :before_oid, :string, limit: 40, null: true
      t.change :after_oid, :string, limit: 40, null: true
      t.change :policy_oid, :string, limit: 40, null: true
    end
  end
end
