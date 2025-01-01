class AddEntitySupportToMemberFeatureRequests < ActiveRecord::Migration[7.2]
  def change
    change_table :member_feature_requests, bulk: true do |t|
      t.bigint :request_entity_id, null: true, unsigned: true, comment: "the entity that the requested feature is for"
      t.string :request_entity_type, limit: 32, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", null: true, comment: "the type of entity"
      t.bigint :billing_entity_id, null: true, unsigned: true, comment: "the billing entity associated with the request entity"
      t.string :billing_entity_type, limit: 32, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", null: true, comment: "the billing entity type"

      t.index [:request_entity_id, :request_entity_type], name: "index_request_entity"
      t.index [:billing_entity_id, :billing_entity_type], name: "index_billing_entity"
    end
  end
end
