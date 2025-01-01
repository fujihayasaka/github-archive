# typed: true

class AddSecurityCampaignsClosureStats < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_table :security_campaigns, bulk: true do |t|
      t.integer :closure_open_count
      t.integer :closure_closed_count
      t.integer :closure_dismissed_count
      t.integer :closure_autofix_supported_count
      t.integer :closure_autofix_generated_count
      t.integer :closure_autofix_accepted_count
    end
  end
end
