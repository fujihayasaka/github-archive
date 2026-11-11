class DropRafNotificationsOrganizationIdColumn < ActiveRecord::Migration[7.2]
  def up
    remove_index :member_feature_request_notifications, name: "index_unique_member_feature_request_notifications"
    change_table :member_feature_request_notifications, bulk: true do |t|
      t.remove :organization_id
    end
  end

  def down
    change_table :member_feature_request_notifications, bulk: true do |t|
      t.bigint :organization_id, null: false, unsigned: true, comment: "organization which the admin belongs to"
    end
    add_index :member_feature_request_notifications, [:user_id, :organization_id, :feature], unique: true, name: "index_unique_member_feature_request_notifications"
  end
end
