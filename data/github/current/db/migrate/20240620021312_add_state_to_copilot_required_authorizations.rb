class AddStateToCopilotRequiredAuthorizations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_required_authorizations, bulk: true do |t|
      t.column :state, :integer, null: false, default: 0
    end
  end
end
