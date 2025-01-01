class AddSecurityCampaignManager < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    add_column :security_campaigns, :manager_id, :bigint, unsigned: true
  end
end
