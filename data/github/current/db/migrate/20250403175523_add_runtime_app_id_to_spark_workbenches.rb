# typed: true
# frozen_string_literal: true

class AddRuntimeAppIdToSparkWorkbenches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :spark_workbenches, bulk: true do |t|
      t.column :runtime_app_id, :bigint, null: true, unsigned: true, comment: "Runtime App this spark deploys to"

      t.index :runtime_app_id, name: "index_spark_workbenches_on_runtime_app_id"
    end
  end
end
