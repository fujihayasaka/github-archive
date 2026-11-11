# typed: true

class UpdateRequiredDeploymentsTableIdToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    change_table :required_deployments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :protected_branch_id, :bigint, unsigned: true, null: false
      t.change :environment_id, :bigint, unsigned: true, default: nil
    end
  end
end
