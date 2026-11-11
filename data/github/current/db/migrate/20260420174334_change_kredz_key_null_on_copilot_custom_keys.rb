# typed: true

class ChangeKredzKeyNullOnCopilotCustomKeys < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_column_null :copilot_custom_keys, :kredz_key, true
  end
end
