# typed: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddAllAllowedAndShaPinningRequiredToActionsAllowlists < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :actions_allowlists, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :entity_id, :bigint, unsigned: true, null: false
      t.column :all_allowed, :boolean, default: false, null: false
      t.column :sha_pinning_required, :boolean, default: false, null: false
    end
  end

  def down
    change_table :actions_allowlists, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.change :entity_id, :integer, null: false
      t.remove :all_allowed
      t.remove :sha_pinning_required
    end
  end
end
