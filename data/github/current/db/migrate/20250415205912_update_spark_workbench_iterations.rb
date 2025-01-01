# typed: true
# frozen_string_literal: true

class UpdateSparkWorkbenchIterations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :spark_workbench_iterations, :parent_id, :bigint, null: true, unsigned: true
  end
end
