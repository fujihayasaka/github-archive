# frozen_string_literal: true

class AddPendingPullRequestUpdateModels < ActiveRecord::Migration[6.0]
  def change
    create_table :pending_pull_request_updates, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :pull_request_id, null: false
      t.text :encrypted_dependency_files, null: false
      t.string :updated_base_commit_sha, null: false
      t.timestamps
    end
  end
end
