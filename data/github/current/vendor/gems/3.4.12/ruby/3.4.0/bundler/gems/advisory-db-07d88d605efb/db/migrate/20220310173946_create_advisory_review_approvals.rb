# frozen_string_literal: true

class CreateAdvisoryReviewApprovals < ActiveRecord::Migration[6.1]
  def change
    create_table :advisory_review_approvals do |t|
      t.bigint :user_id, null: false
      t.bigint :advisory_review_id, null: false
      t.datetime :approved_at

      t.index :user_id
      t.index :advisory_review_id

      t.timestamps
    end
  end
end
