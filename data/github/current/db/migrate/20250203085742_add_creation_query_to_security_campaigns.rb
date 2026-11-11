# typed: strict

class AddCreationQueryToSecurityCampaigns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    add_column :security_campaigns, :creation_query, :text, default: nil, null: true
  end
end
