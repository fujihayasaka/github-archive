class EmbiggenEditorDetailsInUsageDetails < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_aggregate_usage_details, bulk: true do |t|
      t.remove_index name: :index_copilot_aggregate_usage_details_on_organization_id
      t.remove :organization_id # this is not referenced anywhere in code, so we won't add it back

      t.change :editor_details, :string, limit: 200
    end
  end
end
