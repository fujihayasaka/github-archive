# typed: true
class CreateForYouFeedFilterSettings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    create_table :for_you_feed_filter_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false, index: { unique: true }
      t.boolean :announcements_enabled, null: false, default: true
      t.boolean :releases_enabled, null: false, default: true
      t.boolean :sponsors_enabled, null: false, default: true
      t.boolean :stars_enabled, null: false, default: true
      t.boolean :repositories_enabled, null: false, default: true
      t.boolean :follows_enabled, null: false, default: true
      t.boolean :recommendations_enabled, null: false, default: true
      t.boolean :posts_enabled, null: false, default: true
      t.boolean :explicit_only_enabled, null: false, default: true
      t.timestamps
    end
  end

  def down
    drop_table :for_you_feed_filter_settings
  end
end
