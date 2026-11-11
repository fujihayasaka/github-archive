class AddLicenseColumnsToBusinessUserAccounts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    reversible do |dir|
      change_table :business_user_accounts, bulk: true do |t|
        dir.up do
          # Requested changes from GitHub/ExistingIdColumnsMustBeBigint
          t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
          t.change :business_id, :bigint, unsigned: true, null: false
          t.change :user_id, :bigint, unsigned: true, null: true

          # Remaining changes
          t.column :business_roles_bitfield, :int, unsigned: true, null: true
          t.column :ghec_licenses_bitfield, :tinyint, unsigned: true, null: true
          t.index [:business_id, :ghec_licenses_bitfield], name: "index_on_business_id_ghec_licenses_bitfield"
        end

        dir.down do
          # Requested changes from GitHub/ExistingIdColumnsMustBeBigint
          t.change :id, :integer, unsigned: false, null: false, auto_increment: true
          t.change :business_id, :integer, unsigned: false, null: false
          t.change :user_id, :integer, unsigned: false, null: true

          # Remaining changes
          t.remove_index name: "index_on_business_id_ghec_licenses_bitfield"
          t.remove :business_roles_bitfield
          t.remove :ghec_licenses_bitfield
        end
      end
    end
  end
end
