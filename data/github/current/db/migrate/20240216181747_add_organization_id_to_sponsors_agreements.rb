class AddOrganizationIdToSponsorsAgreements < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsors_agreements, bulk: true do |t|
      t.column :organization_id, :bigint, unsigned: true, null: true
    end
  end
end
