# typed: true

class AddClientByokToCopilotPolicies < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :client_byok, :integer, limit: 1, null: false, default: 2,  comment: "Enterprise and org toggle to enable client-side Bring Your Own Key (BYOK)"
    end
  end
end
