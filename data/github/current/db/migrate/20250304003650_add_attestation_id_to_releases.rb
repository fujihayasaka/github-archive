# typed: true

class AddAttestationIdToReleases < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :releases, bulk: true do |t|
      t.column :attestation_id, :bigint, unsigned: true, null: true
      t.column :immutable, :boolean, null: false, default: false
      t.column :deleted_at, :datetime, null: true, precision: 6
    end
  end

  def down
    change_table :releases, bulk: true do |t|
      t.remove :attestation_id
      t.remove :immutable
      t.remove :deleted_at
    end
  end
end
