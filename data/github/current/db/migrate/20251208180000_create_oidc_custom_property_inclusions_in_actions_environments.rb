# typed: true
# frozen_string_literal: true

class CreateOIDCCustomPropertyInclusionsInActionsEnvironments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::OidcSetting)

  def up
    create_table :oidc_custom_property_inclusions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # The source_id refers to either the Org or Enterprise at which this CustomPropertyDefinition is defined
      t.bigint :source_id, null: false, unsigned: true

      # The source_type refers to whether the source_id is an Org (0) or Enterprise (1)
      t.integer :source_type, limit: 1, unsigned: true, null: false

      # The type of the custom property (0 = repo, 1 = org), repo can be defined at the org or enterprise level, org can only be defined at the enterprise level.
      t.integer :property_type, limit: 1, unsigned: true, null: false

      # The name of the custom property
      t.string :custom_property_name, null: false

      t.timestamps

      t.index [:source_id, :source_type, :property_type, :custom_property_name], unique: true, name: "idx_oidc_custom_property_inclusions_unique"
    end
  end

  def down
    drop_table :oidc_custom_property_inclusions
  end
end
