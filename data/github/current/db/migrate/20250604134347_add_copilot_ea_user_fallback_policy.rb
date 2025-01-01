# typed: true
# frozen_string_literal: true

class AddCopilotEaUserFallbackPolicy < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :ea_user_fallback_policy, :integer, limit: 1, null: false, default: 1, comment: 'Defines the fallback policy state for enterprise-assigned users in Copilot configurations when the business selects "No policy" for any policy. Defaults to disabled.'
    end
  end
end
