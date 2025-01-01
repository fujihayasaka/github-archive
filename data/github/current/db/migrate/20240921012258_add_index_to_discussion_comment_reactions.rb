# typed: true
# frozen_string_literal: true

class AddIndexToDiscussionCommentReactions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    change_table :discussion_comment_reactions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :discussion_comment_id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
    end

    add_index :discussion_comment_reactions, :created_at, name: "discussion_comment_reactions_on_created_at"
  end

  def down
    change_table :discussion_comment_reactions, bulk: true do |t|
      t.change :id, :integer, auto_increment: true
      t.change :discussion_comment_id, :integer
      t.change :user_id, :integer
    end

    remove_index :discussion_comment_reactions, name: "discussion_comment_reactions_on_created_at"
  end
end
