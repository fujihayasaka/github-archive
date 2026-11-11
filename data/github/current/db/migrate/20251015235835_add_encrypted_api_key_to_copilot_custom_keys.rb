# typed: true

class AddEncryptedApiKeyToCopilotCustomKeys < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_column :copilot_custom_keys, :encrypted_secret_value, :text
  end
end
