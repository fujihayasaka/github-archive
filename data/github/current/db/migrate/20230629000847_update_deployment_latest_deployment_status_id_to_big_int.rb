# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
class UpdateDeploymentLatestDeploymentStatusIdToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :deployments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :latest_deployment_status_id, :bigint, unsigned: true, default: nil
    end
    change_table :archived_deployments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :latest_deployment_status_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :deployments, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :latest_deployment_status_id, :int, default: nil
    end
    change_table :archived_deployments, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :latest_deployment_status_id, :int, default: nil
    end
  end
end
