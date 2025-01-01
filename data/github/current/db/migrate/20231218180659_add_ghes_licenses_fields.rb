class AddGhesLicensesFields < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::LicensingCollab)

  def change
    change_table :ghes_licenses, bulk: true do |t|
      t.column :support_cluster, :boolean, default: false, null: false
      t.column :support_key, :boolean, default: false, null: false
    end
  end
end
