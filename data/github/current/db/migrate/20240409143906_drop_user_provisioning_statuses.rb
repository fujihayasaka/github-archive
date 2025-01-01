class DropUserProvisioningStatuses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    drop_table :user_provisioning_statuses
  end
end
