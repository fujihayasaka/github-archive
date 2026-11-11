# typed: true
# frozen_string_literal: true

class AddEventsToSparkWorkbenchIterations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :spark_workbench_iterations, bulk: true do |t|
      t.json :events
    end
  end
end
