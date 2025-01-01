# typed: strict

class DropSecurityCampaignsRepositoriesTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    drop_table :security_campaign_repositories, if_exists: true
  end
end
