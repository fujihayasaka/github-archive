class AddStatusToMemberFeatureRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :member_feature_requests, :status, :integer, unsigned: true, default: 0, limit: 1, null: false
  end
end
