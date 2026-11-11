# typed: true
# frozen_string_literal: true

class DropDiscussionPostRepliesTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    drop_table :discussion_post_replies, if_exists: true
  end
end
