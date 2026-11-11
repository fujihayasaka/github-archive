# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

# Adds columns to `repository_advisory_comments` to allow minimizing advisory comments.
# We mirror the columns that are in `issue_comments` table.
# `comment_hidden` tinyint(1) NOT NULL DEFAULT '0',
# `comment_hidden_reason` varbinary(1024) DEFAULT NULL,
# `comment_hidden_classifier` varchar(50) DEFAULT NULL,
# `comment_hidden_by` int DEFAULT NULL,

class AddMinimizeFieldsToRepositoryAdvisoryComments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)
  def change
    change_table :repository_advisory_comments, bulk: true do |t|
      t.column :comment_hidden, :integer, limit: 1, null: false, default: 0,
        comment: "Set to minimize an advisory comment."
      t.column :comment_hidden_reason, "varbinary(1024)", null: true, default: nil,
        comment: "Reason for minimizing an advisory comment."
      t.column :comment_hidden_classifier, "varchar(50)", null: true, default: nil,
        comment: "Dropdown list reason for minimizing an advisory comment."
      t.column :comment_hidden_by, :integer, null: true, default: nil,
        comment: "The user that minimized the comment."
    end
  end
end
