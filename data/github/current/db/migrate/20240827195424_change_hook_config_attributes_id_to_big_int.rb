class ChangeHookConfigAttributesIdToBigInt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Hooks)

  def up
    change_table :hook_config_attributes, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :hook_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :hook_config_attributes, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :hook_id, :int, null: false
    end
  end
end
