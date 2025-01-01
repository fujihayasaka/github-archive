# typed: true

class AddCustomModelSlugToModelsOrganizationAccessRules < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    change_table :models_organization_access_rules, bulk: true do |t|
      t.bigint :custom_key_id, null: true, unsigned: true,
        comment: "custom key the rule targets, if any", after: :catalog_item_key
      t.bigint :custom_model_id, null: true, unsigned: true,
        comment: "custom model the rule targets, if any", after: :custom_key_id
    end
  end
end
