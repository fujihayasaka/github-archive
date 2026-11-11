# typed: true

class UpdateCopilotCustomKeysForEnterprise < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def up
    change_table :copilot_custom_keys, bulk: true do |t|
      t.change_null :organization_id, true
      t.bigint :business_id, unsigned: true, after: :organization_id
      t.remove_index [:organization_id, :kredz_key]
      t.remove_index [:organization_id, :name]
      t.index [:organization_id, :kredz_key]
      t.index [:organization_id, :name]
      t.index [:business_id, :kredz_key]
      t.index [:business_id, :name]
    end
  end

  def down
    change_table :copilot_custom_keys, bulk: true do |t|
      t.remove_index [:business_id, :kredz_key]
      t.remove_index [:business_id, :name]
      t.change_null :organization_id, false
      t.remove :business_id
      t.remove_index [:organization_id, :kredz_key]
      t.remove_index [:organization_id, :name]
      t.index [:organization_id, :kredz_key], unique: true
      t.index [:organization_id, :name], unique: true
    end
  end
end
