class NullableOrgIdMemberFeatureRequestNotifications < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_column :member_feature_request_notifications, :organization_id, :bigint, null: true, unsigned: true, comment: "organization which the admin belongs to"
  end

  def down
    change_column :member_feature_request_notifications, :organization_id, :bigint, null: false, unsigned: true, comment: "organization which the admin belongs to"
  end
end
