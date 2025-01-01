# typed: true

class AddTargetTypeToFgps < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Iam)

  def change
    change_table :fine_grained_permissions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.column :target_type, :string, limit: 60, null: true
    end

  end
end
