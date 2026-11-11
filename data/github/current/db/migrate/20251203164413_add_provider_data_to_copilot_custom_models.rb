# typed: true

class AddProviderDataToCopilotCustomModels < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_custom_models, bulk: true do |t|
      t.text :provider_data, comment: "provider-specific configuration data", after: :custom_key_id
    end
  end
end
