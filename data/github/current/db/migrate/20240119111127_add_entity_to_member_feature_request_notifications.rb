class AddEntityToMemberFeatureRequestNotifications < ActiveRecord::Migration[7.2]
  def change
    change_table :member_feature_request_notifications, bulk: true do |t|
      t.bigint :entity_id, null: true, unsigned: true, comment: "the entity that the notifications belongs to"
      t.string :entity_type, limit: 32, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", null: true, comment: "the type of entity"

      t.index [:entity_id, :entity_type], name: "index_entity_member_feature_request_notifications"
      t.index [:user_id, :entity_id, :entity_type, :feature], name: "index_user_entity_feature_member_feature_request_notifications"
    end
  end
end
