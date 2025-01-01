# typed: true

class AddSamlExternalIdColumnToExternalIdentities < ActiveRecord::Migration[7.2]
  def up
    change_table :external_identities, bulk: true do |t|
      t.column :saml_external_id, "varchar(128)", null: true
      t.index [:saml_external_id, :provider_id, :provider_type]
    end
  end

  def down
    change_table :external_identities, bulk: true do |t|
      t.remove_index [:saml_external_id, :provider_id, :provider_type]
      t.remove :saml_external_id
    end
  end
end
