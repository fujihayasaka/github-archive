class RemoveCodequoteEnabled < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    remove_column :copilot_configurations, :codequote_enabled, :integer
  end
end
