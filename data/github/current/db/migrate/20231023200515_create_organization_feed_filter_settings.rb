class CreateOrganizationFeedFilterSettings < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def up
    create_table :organization_feed_filter_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|

      t.bigint :user_id, unsigned: true, null: false
      t.boolean :releases_enabled, null: false, default: true
      t.boolean :repositories_enabled, null: false, default: true
      t.boolean :repository_activity_enabled, null: false, default: true
      t.timestamps

      t.index [:user_id], name: "index_feed_filter_settings_on_user_id", unique: true
    end
  end

  def down
    drop_table :organization_feed_filter_settings
  end
end
