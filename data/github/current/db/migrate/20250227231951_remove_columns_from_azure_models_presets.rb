# typed: true

class RemoveColumnsFromAzureModelsPresets < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :azure_models_presets, bulk: true do |t|
      t.remove :description
      # This needs a default value before it can be removed due to the model
      t.change :conversation_history, :json, null: true
    end
  end

  def down
    change_table :azure_models_presets, bulk: true do |t|
      t.column :description, :string, null: true
      t.change :conversation_history, :json, null: false
    end
  end
end
