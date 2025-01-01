# typed: true
# frozen_string_literal: true

class CreateRuleSuiteSourceResult < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rule_suite_source_results, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_rule_suite_id, unsigned: true, null: false
      t.bigint :source_id, unsigned: true
      t.string :source_type, limit: 64
      t.column :result, "tinyint(3)", unsigned: true, null: false, default: 0
      t.column :evaluate_result, "tinyint(3)", unsigned: true, null: false, default: 0
      t.timestamps

      t.index [:repository_rule_suite_id, :source_id, :source_type], name: "index_repository_rule_suite_source_results_rule_suite_source", unique: true
    end
  end
end
