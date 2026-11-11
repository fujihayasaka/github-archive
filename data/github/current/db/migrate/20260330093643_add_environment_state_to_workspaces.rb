# typed: true
# frozen_string_literal: true

class AddEnvironmentStateToWorkspaces < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :workspaces, bulk: true do |t|
      t.virtual :environment_state, type: :string, limit: 64,
                as: "JSON_UNQUOTE(JSON_EXTRACT(`environment_data`, '$.state'))"
    end
  end
end
