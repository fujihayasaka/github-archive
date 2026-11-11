# typed: true
# frozen_string_literal: true

class AddSnapshotIdToSparkWorkbenches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :spark_workbenches, :last_snapshot_environment_id, :bigint, unsigned: true, null: true
  end
end
