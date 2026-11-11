# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewRepoEnablements < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_code_review_repo_enablements, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :owner_id, null: false, unsigned: true, comment: "The ID of the owner of the repository"
      t.bigint   :repository_id, null: false, unsigned: true, comment: "The ID of the enabled repository"
      t.integer  :setting_type, null: false, comment: "The type of Copilot code review repository setting that is enabled"
      t.datetime :created_at, null: false, precision: 6, comment: "The time when the feature was enabled for this repository"

      t.index [:repository_id, :owner_id, :setting_type], unique: true, name: "idx_ccr_repo_enablements_on_repo_owner_setting"
      t.index [:owner_id, :setting_type], name: "idx_ccr_repo_enablements_on_owner_setting"
    end
  end
end
