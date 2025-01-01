# typed: true
# frozen_string_literal: true

class AddSuggestionsToSparkWorkbenchIterations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :spark_workbench_iterations, :suggestions, :json, null: true
  end
end
