# typed: true

class AddDesktopCopilotPolicy < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :desktop, :integer, limit: 1, null: false, default: 0
    end
  end
end
