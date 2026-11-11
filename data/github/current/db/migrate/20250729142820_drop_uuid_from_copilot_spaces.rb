# typed: true

class DropUUIDFromCopilotSpaces < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    remove_column :custom_copilots, :uuid, :string, null: true, default: nil
  end
end
