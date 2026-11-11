# typed: true
# frozen_string_literal: true

class AddClosedAtToSecurityCampaigns < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_table :security_campaigns, bulk: true do |t|
      t.datetime :closed_at, precision: 6
      t.index :closed_at, name: "index_security_campaigns_on_closed_at"
    end
  end
end
