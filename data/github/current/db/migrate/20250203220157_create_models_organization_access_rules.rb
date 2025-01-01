# typed: true

class CreateModelsOrganizationAccessRules < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table(:models_organization_access_rules,
      id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci",
    ) do |t|
      t.bigint :organization_id, null: false, unsigned: true
      t.boolean :allow, null: false, comment: "whether this rule allows or blocks access"
      t.bigint :models_publisher_id, unsigned: true, comment: "the publisher whose models the rule targets, if any"
      t.string :catalog_item_key, limit: 1024, comment: "the specific model the rule targets, if any"
      t.timestamps

      t.index [:organization_id, :allow, :models_publisher_id]
      t.index :models_publisher_id
    end
  end
end
