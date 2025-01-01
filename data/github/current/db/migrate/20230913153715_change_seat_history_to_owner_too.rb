class ChangeSeatHistoryToOwnerToo < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seat_histories, bulk: true do |t|
      # TODO: Deprecate this column (and business_id) in favor of owner_id and owner_type
      t.change :organization_id, :bigint, null: true

      # add in new polymorphic column for owner (business or organization)
      # for legacy enterprise associated orgs and standalone orgs, we make the owner = org
      # for enterprise teams, we make the owner = enterprise
      t.column :owner_id, :bigint, null: true, unsigned: true, after: :id
      t.column :owner_type, :string, null: true, after: :owner_id
    end
  end
end
