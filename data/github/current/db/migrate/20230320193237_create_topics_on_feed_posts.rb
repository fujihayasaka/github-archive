# typed: true
class CreateTopicsOnFeedPosts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    add_column :feed_posts, :topic_id, :bigint, unsigned: true, null: true
  end
end
