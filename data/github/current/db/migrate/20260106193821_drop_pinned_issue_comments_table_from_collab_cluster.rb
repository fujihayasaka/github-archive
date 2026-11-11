# typed: true
# frozen_string_literal: true

class DropPinnedIssueCommentsTableFromCollabCluster < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :pinned_issue_comments
  end
end
