# typed: true

class AddDraftAbilityToSecurityCampaigns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_table :security_campaigns, bulk: true do |t|
      # Allow description and ends_at to be nullable
      t.change_null :description, true
      t.change_null :ends_at, true

      # Add new property to mark when a draft campaign gets published
      t.datetime :published_at, null: true, precision: 6
    end
  end
end
