class AddUniverseCopilotPolicies < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :dotcom_chat, :integer, limit: 1, null: false, default: 0
      t.column :custom_models, :integer, limit: 1, null: false, default: 0
      t.column :cli, :integer, limit: 1, null: false, default: 0
      t.column :private_docs, :integer, limit: 1, null: false, default: 0
    end
  end
end
