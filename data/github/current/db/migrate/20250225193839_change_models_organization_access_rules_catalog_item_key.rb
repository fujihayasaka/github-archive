# typed: true

class ChangeModelsOrganizationAccessRulesCatalogItemKey < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def up
    change_table :models_organization_access_rules, bulk: true do |t|
      t.change :catalog_item_key, :string, limit: 80, null: true
      t.index :catalog_item_key
    end
  end

  def down
    change_table :models_organization_access_rules, bulk: true do |t|
      t.remove_index :catalog_item_key
      t.change :catalog_item_key, :string, limit: 1024, null: true
    end
  end
end
