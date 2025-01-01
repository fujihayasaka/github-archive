# typed: true
# frozen_string_literal: true

class ChangeColumnNullSparkWorkbenchesCloudEnvironmentId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :spark_workbenches, bulk: true do |t|
      t.text :description, null: true
      t.change :cloud_environment_id, :bigint, null: true, unsigned: true
    end
  end

  def down
    change_table :spark_workbenches, bulk: true do |t|
      t.remove :description
      t.change :cloud_environment_id, :bigint, null: false, unsigned: true
    end
  end
end
