# typed: true
# frozen_string_literal: true

class AddCopilotPolicyDefaultColumns < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :models_default, :integer, limit: 1, null: false, default: 2,
        comment: "Default setting for model policies. Customers can configure this to automatically enable/disable new models."

      t.column :features_default, :integer, limit: 1, null: false, default: 2,
        comment: "Default setting for feature policies. Customers can configure this to automatically enable/disable new features."
    end
  end
end
