# typed: true

class AddTransportsBackupEligibleBackupStateToU2fRegistrations < ActiveRecord::Migration[7.1]
  def up
    change_table(:u2f_registrations, bulk: true) do |t|
      t.column :transports, :json, null: true
      t.column :backup_eligibility, :boolean, null: true
      t.column :backup_state, :boolean, null: true
      t.change :resident_key, :boolean, default: nil, null: true
      t.remove :platform_scope
      # These changes are not part of our core changes but have been requested
      # as part of all migrations. See https://thehub.github.com/engineering/products-and-services/dotcom/migrations-and-transitions/database-migrations-for-dotcom/#changes-to-existing-tables
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table(:u2f_registrations, bulk: true) do |t|
      t.remove :transports
      t.remove :backup_eligibility
      t.remove :backup_state
      t.change :resident_key, :boolean, default: false, null: false
      t.add :u2f_registrations, :platform_scope, :string, limit: 32, null: true
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int, null: false
    end
  end
end
