class AddDismissToMemberFeatureRequests < ActiveRecord::Migration[7.2]
  def change
    change_table :member_feature_requests, bulk: true do |t|
      t.bigint :dismissed_by_id, null: true, unsigned: true, comment: "the actor who dismissed the request"
      t.datetime :dismissed_at, null: true, precision: 6
    end
  end
end
