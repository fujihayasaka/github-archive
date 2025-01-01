# typed: true
# frozen_string_literal: true

class RevertIssueReactionsEnumChanges < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def up
    execute <<-SQL
      ALTER TABLE issue_reactions
      MODIFY COLUMN `content` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE issue_reactions
      MODIFY COLUMN `content` enum('eyes', 'tada', '-1', 'heart', '+1', 'rocket', 'thinking_face', 'smile') NOT NULL;
    SQL
  end
end
