# typed: true
# frozen_string_literal: true

class CreateActionsRulesets < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def change
    create_table :actions_rulesets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 255, null: false
      t.bigint :source_id, null: false, unsigned: true
      t.string :source_type, limit: 100, null: false
      t.column :target, "tinyint(3)", unsigned: true, null: false, default: 0
      t.column :enforcement, "tinyint(3)", unsigned: true, null: false, default: 0
      t.timestamps

      t.index [:source_id, :source_type, :name], unique: true, name: "index_actions_rulesets_on_source_and_name"
    end
  end
end
