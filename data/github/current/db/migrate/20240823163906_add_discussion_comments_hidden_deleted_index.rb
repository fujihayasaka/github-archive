# typed: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddDiscussionCommentsHiddenDeletedIndex < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :discussion_comments, bulk: true do |t|
      t.boolean :deleted, null: false, as: "deleted_at IS NOT NULL", after: :deleted_at
      t.index [:discussion_id, :user_hidden, :comment_hidden, :deleted]
    end
  end

  def down
    change_table :discussion_comments, bulk: true do |t|
      t.remove_index [:discussion_id, :user_hidden, :comment_hidden, :deleted_at]
      t.remove_column :deleted
    end
  end
end
