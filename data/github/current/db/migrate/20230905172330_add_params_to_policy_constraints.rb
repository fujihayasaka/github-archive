class AddParamsToPolicyConstraints < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Policies)
  def change
    add_column :policy_constraints, :params, :json, null: true
  end
end
