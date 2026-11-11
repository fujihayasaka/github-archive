# typed: true

class RemoveManagerIdFromSecurityCampaigns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def up
    remove_column :security_campaigns, :manager_id
  end

  def down
    add_column :security_campaigns, :manager_id, :bigint, unsigned: true
  end
end
