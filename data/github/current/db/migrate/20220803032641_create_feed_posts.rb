# typed: true

class CreateFeedPosts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :feed_posts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, unsigned: true, null: false, index: true
      t.bigint :author_id, unsigned: true, null: false
      t.column :body, :mediumblob, null: false
      t.column :hidden, "tinyint(4)", default: 0, null: false

      t.timestamps
    end
  end
end
