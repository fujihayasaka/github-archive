# typed: true
# frozen_string_literal: true

class AddCurrentIterationIdToSparkWorkbenches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :spark_workbenches, :current_iteration_id, :bigint, null: true, unsigned: true
  end
end
