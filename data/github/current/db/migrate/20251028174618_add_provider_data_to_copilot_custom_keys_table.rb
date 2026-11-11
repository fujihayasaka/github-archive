# typed: true

class AddProviderDataToCopilotCustomKeysTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_custom_keys, bulk: true do |t|
      t.text :provider_data, comment: "provider-specific configuration data"
    end
  end
end
