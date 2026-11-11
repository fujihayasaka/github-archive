# typed: true

class CreateTopicFeedFilterSettings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def up
    create_table :feed_filter_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.boolean :is_topic, null: false, default: false
      t.boolean :announcements_enabled, null: false, default: true
      t.boolean :releases_enabled, null: false, default: true
      t.boolean :sponsors_enabled, null: false, default: true
      t.boolean :stars_enabled, null: false, default: true
      t.boolean :repositories_enabled, null: false, default: true
      t.boolean :repository_activity_enabled, null: false, default: false
      t.boolean :follows_enabled, null: false, default: true
      t.boolean :recommendations_enabled, null: false, default: true
      t.boolean :posts_enabled, null: false, default: true
      t.boolean :explicit_only_enabled, null: false, default: true
      t.timestamps

      t.index [:user_id], name: "index_feed_filter_settings_on_user_id"
    end
  end

  def down
    drop_table :feed_filter_settings
  end
end
