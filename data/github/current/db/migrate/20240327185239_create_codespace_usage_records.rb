class CreateCodespaceUsageRecords < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    create_table :codespace_usage_records, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :owner, polymorphic: true, null: false, index: true
      t.references :billable_owner, polymorphic: true, null: false, index: true
      t.column     :codespace_guid, "char(36)", null: false, index: true
      t.column     :copilot_workspace_id, "char(36)", default: nil, index: true
      t.datetime   :start_at, precision: 6, null: false, index: true
      t.datetime   :end_at, precision: 6, null: false, index: true
      t.integer    :usage_seconds, default: 0, unsigned: true
      t.timestamps
    end
  end
end
