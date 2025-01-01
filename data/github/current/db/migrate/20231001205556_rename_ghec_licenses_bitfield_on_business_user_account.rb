class RenameGhecLicensesBitfieldOnBusinessUserAccount < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    reversible do |dir|
      change_table :business_user_accounts, bulk: true do |t|
        dir.up do
          t.remove_index name: "index_on_business_id_ghec_licenses_bitfield"
          t.remove :ghec_licenses_bitfield

          t.column :ghec_license, :tinyint, unsigned: true, null: true
          t.index [:business_id, :ghec_license], name: "index_business_user_accounts_on_business_id_ghec_license"
        end

        dir.down do
          t.column :ghec_licenses_bitfield, :tinyint, unsigned: true, null: true
          t.index [:business_id, :ghec_licenses_bitfield], name: "index_on_business_id_ghec_licenses_bitfield"

          t.remove_index name: "index_business_user_accounts_on_business_id_ghec_license"
          t.remove :ghec_license
        end
      end
    end
  end
end
