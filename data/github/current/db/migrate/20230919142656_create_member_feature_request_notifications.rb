# typed: true

class CreateMemberFeatureRequestNotifications < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :member_feature_request_notifications, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: false, unsigned: true, comment: "organization admin who receives the request a feature notification"
      t.bigint :organization_id, null: false, unsigned: true, comment: "organization which the admin belongs to"
      t.column :feature, "tinyint unsigned", null: false, comment: "enum representing the notification feature"
      t.integer :feature_request_count, null: false, unsigned: true, comment: "the number of feature requests for the notification"

      t.timestamps
    end

    add_index :member_feature_request_notifications, [:user_id, :organization_id, :feature], unique: true, name: "index_unique_member_feature_request_notifications"
  end
end
