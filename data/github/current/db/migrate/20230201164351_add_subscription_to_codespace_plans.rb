# typed: true
class AddSubscriptionToCodespacePlans < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_column :workspace_plans, :subscription, :string, null: false, limit: 36, default: ""
  end
end
