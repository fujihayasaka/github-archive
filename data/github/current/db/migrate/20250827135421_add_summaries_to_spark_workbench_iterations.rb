# typed: true
# frozen_string_literal: true

class AddSummariesToSparkWorkbenchIterations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table(:spark_workbench_iterations, bulk: true) do |t|
      t.column :intent_summary, :json, null: true
      t.column :completion_summary, :json, null: true
    end
  end
end
