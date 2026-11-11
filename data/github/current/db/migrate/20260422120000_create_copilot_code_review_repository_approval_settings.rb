# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewRepositoryApprovalSettings < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_code_review_repository_approval_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.boolean :repo_auto_approve_when_delegated, null: false, default: false
      t.boolean :repo_qualified_approval_when_delegated, null: false, default: false
      t.string :repo_qualified_approval_scope_when_enabled, null: false, default: "all_files"
      t.text :repo_qualified_approval_file_patterns
      t.timestamps

      t.index :repository_id, unique: true, name: "index_ccr_repo_approval_settings_on_repo_id"
    end
  end
end
