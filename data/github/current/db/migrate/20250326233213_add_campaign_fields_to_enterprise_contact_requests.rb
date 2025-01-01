# typed: true
# frozen_string_literal: true

class AddCampaignFieldsToEnterpriseContactRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Site)

  def change
    change_table :enterprise_contact_requests, bulk: true do |t|
      t.string :cdl_program_name, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.string :sfdc_last_campaign_status, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.string :source, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.string :direct_to_sfdc_campaign_id, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
    end
  end
end
