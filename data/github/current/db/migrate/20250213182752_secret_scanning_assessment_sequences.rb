# typed: true

class SecretScanningAssessmentSequences < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_assessment_sequences, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :owner_scope_id, primary_key: true, null: false, unsigned: true, auto_increment: false
      t.integer   :number, default: 0, null: false, unsigned: true
      t.datetime  :updated_at, null: false, precision: 6
    end
  end
end
