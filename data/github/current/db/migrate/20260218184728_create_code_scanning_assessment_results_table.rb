# typed: true
# frozen_string_literal: true

class CreateCodeScanningAssessmentResultsTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :code_scanning_assessment_results, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :assessment_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true
      t.string :rule_id, null: false, limit: 255
      t.string :rule_name, null: false, limit: 255
      t.string :language, null: false, limit: 100
      t.boolean :autofix_supported, default: false, null: false
      t.string :severity, null: false, limit: 12
      t.integer :vulnerability_count, default: 0, null: false
      t.timestamps

      t.index [:assessment_id, :repository_id, :rule_id], name: "index_csra_results_unique", unique: true
    end
  end
end
