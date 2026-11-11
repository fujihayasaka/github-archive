# typed: true
# frozen_string_literal: true

class CreateSparkWorkbenchIterations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :spark_workbench_iterations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :spark_workbench_id, null: false, unsigned: true
      t.blob :prompt, null: true, default: nil
      t.string :sha, null: true, default: nil
      t.column :iteration_type, :tinyint, unsigned: true, null: true, default: nil
      t.timestamps

      t.index :spark_workbench_id, name: "index_spark_workbench_iterations_on_spark_workbench_id"
    end
  end
end
