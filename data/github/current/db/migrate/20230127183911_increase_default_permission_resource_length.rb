# typed: true
class IncreaseDefaultPermissionResourceLength < ActiveRecord::Migration[7.1]
  def up
    change_table(:default_integration_permissions, bulk: true) do |t|
      t.change :resource, :string, limit: 60
      t.change :id, :bigint, unsigned: true
      t.change :integration_id, :bigint, unsigned: true
      t.change :integration_version_id, :bigint, unsigned: true
    end
  end

  def down
    change_table(:default_integration_permissions, bulk: true) do |t|
      t.change :resource, :string, limit: 40
      t.change :id, :int
      t.change :integration_id, :int
      t.change :integration_version_id, :int
    end
  end
end
