# frozen_string_literal: true

class MigrateUpdateDependenciesToMatchUpdateConfigs < ActiveRecord::Migration[7.0]
  def up
    change_table :updated_dependencies, bulk: true do |t|
      t.change :directory, "varbinary(1024)", null: true, collation: "binary"
    end
  end

  def down
    change_table :updated_dependencies, bulk: true do |t|
      t.change :directory, "varchar(255)", null: true, collation: "utf8mb4_general_ci"
    end
  end
end
