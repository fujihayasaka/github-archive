# typed: true

class AddInlineApprovalEnabledToCopilotModelRegistryCache < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :model_registry_cache, :inline_approval_enabled, :boolean, null: false, default: false, comment: "Indicates if inline approval is enabled for the model"
  end
end
