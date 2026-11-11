# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class MigrateReviewRequestReasonsForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :review_request_reasons, bulk: true do |t|
      t.change :codeowners_tree_oid, :string, limit: 64, null: true
    end

    change_table :archived_review_request_reasons, bulk: true do |t|
      t.change :codeowners_tree_oid, :string, limit: 64, null: true
    end
  end

  def down
    change_table :review_request_reasons, bulk: true do |t|
      t.change :codeowners_tree_oid, :string, limit: 40, null: true
    end

    change_table :archived_review_request_reasons, bulk: true do |t|
      t.change :codeowners_tree_oid, :string, limit: 40, null: true
    end
  end
end
