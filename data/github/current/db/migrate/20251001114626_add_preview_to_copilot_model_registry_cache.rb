# typed: strict

class AddPreviewToCopilotModelRegistryCache < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  sig { void }
  def change
    add_column :model_registry_cache, :preview, :boolean, null: false, default: true, comment: "Indicates if the model is a preview model"
  end
end
