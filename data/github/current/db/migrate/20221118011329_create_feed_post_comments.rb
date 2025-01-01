# typed: true

class CreateFeedPostComments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :feed_post_comments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :feed_post_id, unsigned: true, null: false
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :parent_comment_id, unsigned: true, default: nil
      t.column :body, :mediumblob, null: false
      t.datetime :deleted_at, default: nil, precision: 6

      t.timestamps
    end

    add_index :feed_post_comments, [:feed_post_id, :deleted_at, :created_at],
      name: "index_post_comment_on_post_id_deleted_created"

    add_index :feed_post_comments, [:parent_comment_id, :deleted_at, :created_at],
      name: "index_feed_post_comments_on_parent_deleted_created"
  end
end
