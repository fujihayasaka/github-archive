# typed: true
# frozen_string_literal: true

class AddAlertTypeToSecurityCampaigns < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    change_table :security_campaigns, bulk: true do |t|
      t.column :alert_type, "tinyint", unsigned: true, null: false, default: 1, comment: "internal enum describing the type of security alerts associated with the campaign"
    end
  end
end
