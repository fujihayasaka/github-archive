# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddNumberIndexToSecurityCampaigns < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_table :security_campaigns, bulk: true do |t|
      t.remove_index [:organization_id]
      t.index [:organization_id, :number], unique: true
      t.change :number, :int, null: false
    end
  end
end
