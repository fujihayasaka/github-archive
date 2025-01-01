# typed: true

class SecretScanningAssessments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_assessments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :owner_scope_id, null: false, unsigned: true, comment: "The owner that this assessment is for"
      t.integer   :number,     null: false, unsigned: true, comment: "The sequence number of the assessment"
      t.datetime  :created_at, null: false, precision: 6
      t.datetime  :updated_at, null: false, precision: 6
      t.bigint    :parent_assessment_id, unsigned: true, comment: "The parent assessment ID, if this assessment was part of an enterprise/business assessment, otherwise null"
      t.bigint    :requested_by, null: false, unsigned: true, comment: "The actor ID that requested this assessment"
      t.json      :job_group_ids, comment: "an array (e.g., [1,2,3] ) of job group IDs tied to this assessment"

      t.index [:owner_scope_id, :number], unique: true, name: "uq_owner_scope_number"
      t.index :parent_assessment_id, name: "idx_parent_assessment_id"
    end
  end
end
