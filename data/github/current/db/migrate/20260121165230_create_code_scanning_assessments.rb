# typed: true
# frozen_string_literal: true

class CreateCodeScanningAssessments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :code_scanning_assessments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, unsigned: true, null: false
      t.integer :number, unsigned: true, null: false
      t.bigint :requested_by_id, unsigned: true, null: false
      t.integer :status, null: false, unsigned: true, limit: 1

      t.timestamps

      t.index [:owner_id, :number], unique: true, name: "index_owner_id_and_number"
    end
  end
end
