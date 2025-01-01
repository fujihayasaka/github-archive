# typed: true
# frozen_string_literal: true

class AddIssueReactionsCoveringIndices < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def up
    execute <<-SQL
      ALTER TABLE issue_reactions
      MODIFY COLUMN `content` enum('eyes', 'tada', '-1', 'heart', '+1', 'rocket', 'thinking_face', 'smile') NOT NULL,
      ADD INDEX `idx_issue_id_user_hidden_content_created_at` (`issue_id`, `user_hidden`, `content`, `created_at`),
      ADD INDEX `idx_issue_id_content_user_hidden_created_at_id_user_id` (`issue_id`, `content`, `user_hidden`, `created_at`, `id`, `user_id`);
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE issue_reactions
      MODIFY COLUMN `content` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
      DROP INDEX `idx_issue_id_user_hidden_content_created_at`,
      DROP INDEX `idx_issue_id_content_user_hidden_created_at_id_user_id`;
    SQL
  end
end
