# typed: true
# frozen_string_literal: true

class CreateSecurityCampaignIssues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    create_table :security_campaign_issues, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :security_campaign_id,  unsigned: true, null: false
      t.bigint  :repository_id,  unsigned: true, null: false
      t.bigint  :issue_id,  unsigned: true, null: false

      t.timestamps

      t.index [:security_campaign_id, :repository_id], unique: true, name: "index_sc_issues_on_sc_id_and_repo_id"
    end
  end
end
