# typed: true
# frozen_string_literal: true

class CreateActionsRulesetHistories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def change
    create_table :actions_ruleset_histories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :actions_ruleset_id, null: false, unsigned: true
      t.json :state, null: false
      t.bigint :updated_by_id, null: false, unsigned: true
      t.timestamps

      t.index [:actions_ruleset_id, :created_at], name: "index_actions_ruleset_histories_on_ruleset_id_created"
      t.index [:created_at], name: "index_actions_ruleset_histories_created_at"
    end
  end
end
