# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewRepositorySettings < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_code_review_repository_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.boolean :repo_custom_instructions_enabled, null: false, default: true
      t.timestamps
      t.index [:repository_id, :repo_custom_instructions_enabled], unique: true, name: "index_ccr_repo_settings_on_repo_id_custom_instructions_enabled"
    end
  end
end
