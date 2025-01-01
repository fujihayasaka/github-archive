# typed: true

class CreateFeedPostReferences < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :feed_post_references, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :reference_id, unsigned: true, null: false
      t.column :reference_type, "tinyint(4)", null: false
      t.bigint :feed_post_id, unsigned: true, null: false

      t.timestamps
    end

    add_index :feed_post_references, [:feed_post_id, :reference_id, :reference_type],
      name: "index_feed_post_references_on_post_and_reference",
      if_not_exists: true
  end
end
