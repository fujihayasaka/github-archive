# typed: true
class AddCopilotOnlyToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :copilot_only, :boolean, null: false, default: false
  end
end
