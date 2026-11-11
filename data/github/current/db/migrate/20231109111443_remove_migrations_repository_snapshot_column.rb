class RemoveMigrationsRepositorySnapshotColumn < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Migrations

  def change
    reversible do |direction|
      change_table :migrations, bulk: true do |t|
        direction.up do
          t.remove :repository_snapshot
          t.remove_index :repository_snapshot
        end

        direction.down do
          t.boolean :repository_snapshot, null: false, default: false
          t.index :repository_snapshot
        end
      end
    end
  end
end
