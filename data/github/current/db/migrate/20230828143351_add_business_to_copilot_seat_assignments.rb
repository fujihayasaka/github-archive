class AddBusinessToCopilotSeatAssignments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seat_assignments, bulk: true do |t|
      # TODO: Deprecate this column in favor of owner_id and owner_type
      t.change :organization_id, :bigint, null: true

      # add in new polymorphic column for owner (business or organization)
      # for legacy enterprise associated orgs and standalone orgs, we make the owner = org
      # for enterprise teams, we make the owner = enterprise
      t.column :owner_id, :bigint, null: true, unsigned: true, after: :id
      t.column :owner_type, :string, null: true, after: :owner_id

      # first step in getting rid of this column
      t.change :assigning_user_id, :bigint, null: true
      t.remove_index name: "index_copilot_seat_assignments_on_assigning_user_id"

      # add index for polymorphic column
      t.index [:owner_id, :owner_type], name: "index_copilot_seat_assignments_on_owner_id_and_owner_type"
    end
  end
end
