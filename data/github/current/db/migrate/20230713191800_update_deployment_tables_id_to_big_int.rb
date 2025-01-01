# typed: true

class UpdateDeploymentTablesIdToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :archived_deployments, bulk: true do |t|
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :creator_id, :bigint, unsigned: true, null: false
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
      t.change :environment_id, :bigint, unsigned: true, default: nil
      t.change :latest_environment_id, :bigint, unsigned: true, default: nil
    end

    change_table :deployments, bulk: true do |t|
      t.change :repository_id, :bigint, unsigned: true, null: false
      t.change :creator_id, :bigint, unsigned: true, null: false
      t.change :performed_by_integration_id, :bigint, unsigned: true, default: nil
      t.change :environment_id, :bigint, unsigned: true, default: nil
      t.change :latest_environment_id, :bigint, unsigned: true, default: nil
    end
  end
end
