# typed: true
# frozen_string_literal: true

class CreateCopilotConditionExpressionsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_condition_expressions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :targetable_attribute, limit: 255, null: false
      t.string :operation, limit: 255, null: false
      t.text :value, null: false
      t.bigint :root_condition_expression_id, unsigned: true
      t.bigint :parent_condition_expression_id, unsigned: true
      t.timestamps

      t.index [:root_condition_expression_id], name: "index_copilot_condition_expressions_on_root_condition"
      t.index [:parent_condition_expression_id], name: "index_copilot_condition_expressions_on_parent_condition"
    end
  end
end
