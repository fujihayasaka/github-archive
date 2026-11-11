class AddBusinessToCopilotSeatEmissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seat_emissions, bulk: true do |t|
      # TODO: Deprecate this column in favor of owner_id and owner_type
      t.change :organization_id, :bigint, null: true

      # add in new polymorphic column for owner (business or organization)
      # for legacy enterprise associated orgs and standalone orgs, we make the owner = org
      # for enterprise teams, we make the owner = enterprise
      t.column :owner_id, :bigint, null: true, unsigned: true, after: :id
      t.column :owner_type, :string, null: true, after: :owner_id

      t.index [:owner_id, :owner_type], name: "index_copilot_seat_assignments_on_owner_id_and_owner_type"
    end
  end
end
