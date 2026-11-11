# typed: true
# frozen_string_literal: true

class AddSparkWorkbenchIdToWorkspaces < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :workspaces, bulk: true do |t|
      t.virtual :spark_workbench_id, type: :string, limit: 64,
                as: "JSON_UNQUOTE(JSON_EXTRACT(`linked_resources`, '$.spark_workbench_id'))"
    end
  end
end
