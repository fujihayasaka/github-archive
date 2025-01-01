# typed: true

class DropUsageDetails < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    drop_table :copilot_usage_details
  end
end
