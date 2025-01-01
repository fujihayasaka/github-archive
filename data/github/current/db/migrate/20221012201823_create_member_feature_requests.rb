# typed: true
class CreateMemberFeatureRequests < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :member_feature_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :requester_id, null: false, unsigned: true, comment: "the user which is requesting the feature"
      t.bigint :organization_id, null: false, unsigned: true, comment: "the organization which the user belongs to"
      t.column :feature, "tinyint unsigned", null: false, comment: "enum representing the feature user requested"

      t.timestamps
    end

    add_index :member_feature_requests, :organization_id
    add_index :member_feature_requests, [:requester_id, :organization_id, :feature], unique: true, name: "index_unique_member_feature_request"
  end
end
