# typed: true

class AddVendorToCopilotModelRegistryCache < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :model_registry_cache, :vendor, :string, limit: 32, null: false, default: "Unknown", comment: "Indicates what vendor (e.g. OpenAI, Anthropic, etc.) the model is from"
  end
end
