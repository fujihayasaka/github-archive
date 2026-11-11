# frozen_string_literal: true

class ChangeUpdateConfigsToVarbinary1024 < ActiveRecord::Migration[7.0]
  def up
    change_table :update_configs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :directory, "varbinary(1024)", null: false, collation: "binary"
    end
  end

  def down
    change_table :update_configs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.change :directory, "varchar(255)", null: false, collation: "utf8mb4_general_ci"
    end
  end
end
