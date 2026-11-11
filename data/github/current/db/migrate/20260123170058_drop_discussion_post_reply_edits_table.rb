# typed: true
# frozen_string_literal: true

class DropDiscussionPostReplyEditsTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    drop_table :discussion_post_reply_edits, if_exists: true
  end
end
