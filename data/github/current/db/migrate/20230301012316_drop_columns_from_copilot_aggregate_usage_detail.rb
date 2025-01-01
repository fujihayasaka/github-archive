# typed: true

class DropColumnsFromCopilotAggregateUsageDetail < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_aggregate_usage_details, bulk: true do |t|
      t.remove_index name: :index_aggregate_on_everything
      t.remove :repository_id
      t.remove :blocked_remote_repository_id

      t.index [:user_id, :organization_id, :editor_details, :usage_date], name: "index_user_org_editor_date_details", unique: true
    end
  end
end
