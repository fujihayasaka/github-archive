# typed: true
# frozen_string_literal: true

class CreateArtifactClusterJobs < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    create_table :artifact_cluster_jobs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false
      t.column :actor_id, :bigint, unsigned: true, null: true
      t.column :integration_id, :bigint, unsigned: true, null: true
      t.column :cluster, :string, null: false, limit: 128
      t.column :logical_environment, :string, null: false, limit: 128
      t.column :physical_environment, :string, null: false, limit: 128, default: ""
      t.column :status, :string, null: false, default: "pending"
      t.column :total_count, :integer, default: 0
      t.column :job_errors, :json, null: true
      t.column :accepted_deployments, :json, null: true
      t.column :enqueued_at, :datetime, precision: 6, null: false
      t.column :started_at, :datetime, precision: 6, null: true
      t.timestamps
      t.index [:owner_id, :cluster, :created_at], name: "idx_cluster_jobs_owner_cluster_created"
      t.index [:owner_id, :cluster, :status], name: "idx_cluster_jobs_owner_cluster_status"
    end
  end
end
