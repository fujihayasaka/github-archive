# typed: true
# frozen_string_literal: true

class CreateCodeScanningAssessmentRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :code_scanning_assessment_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :assessment_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true
      t.integer :status, null: false, unsigned: true, limit: 1
      t.string :failure_reason, limit: 255
      t.timestamps

      t.index [:assessment_id, :repository_id], unique: true, name: "index_assessment_id_and_repository_id"
      t.index [:assessment_id, :status], name: "index_assessment_id_and_status"
    end
  end
end
