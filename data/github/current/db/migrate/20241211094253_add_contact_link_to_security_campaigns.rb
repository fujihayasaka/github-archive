# typed: true

class AddContactLinkToSecurityCampaigns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    add_column :security_campaigns, :contact_link, :text
  end
end
