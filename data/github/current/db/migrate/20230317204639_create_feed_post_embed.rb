# typed: true
class CreateFeedPostEmbed < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :feed_post_embeds, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :subject_id, :bigint, unsigned: true, null: false
      t.column :subject_type, "varchar(255)", null: false
      t.column :title, "varchar(1024)", null: false
      t.column :description, :blob, null: false
      t.column :url, :text, null: false
      t.column :site_name,  "varchar(1024)"
      t.column :image_url, :text

      t.timestamps
    end

    add_index :feed_post_embeds, [:subject_id, :subject_type]
  end
end
