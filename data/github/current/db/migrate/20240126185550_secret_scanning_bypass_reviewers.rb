# typed: true
# frozen_string_literal: true

class SecretScanningBypassReviewers < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table(:secret_scanning_bypass_reviewers, id: :bigint, unsigned: true, charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci"
    ) do |t|
      t.bigint :owner_scope_id, unsigned: true, null: false, comment: "What exactly is bypassed. Repo or org"
      t.bigint :reviewer_id, unsigned: true, null: false, comment: "The bypass reviewer ID"
      t.column :reviewer_type, :tinyint, unsigned: true, null: false, comment: "The bypass reviewer type. See BypassReviewerType enum"
      t.datetime :created_at, null: false, precision: 6

      t.index [:owner_scope_id, :reviewer_id, :reviewer_type], unique: true
    end
  end
end
