# typed: true
# frozen_string_literal: true

class AddUniqueIndexOnDisplayNameAndUserIdToMcpServerConfigs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :mcp_server_configs, bulk: true do |t|
      t.change_null :display_name, false
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:user_id, :display_name], unique: true
      # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
    end
  end
end
