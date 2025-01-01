# typed: strict

class AddSecurityCampaignsUserHiddenAndCreatedById < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    change_table :security_campaigns, bulk: true do |t|
      t.boolean :user_hidden, default: false, null: false
      t.bigint :created_by_id, null: true, unsigned: true

      t.index [:created_by_id, :user_hidden], name: "index_security_campaigns_on_created_by_id_and_user_hidden"
    end
  end
end
