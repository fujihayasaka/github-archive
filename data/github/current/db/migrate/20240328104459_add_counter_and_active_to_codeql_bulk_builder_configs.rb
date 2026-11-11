class AddCounterAndActiveToCodeqlBulkBuilderConfigs < ActiveRecord::Migration[7.2]
  def change
    change_table(:codeql_bulk_builder_configs, bulk: true) do |t|
      t.column :is_active, :boolean, default: true, null: false
      t.column :consecutive_build_failures, :int, default: 0, null: false
    end
  end
end
