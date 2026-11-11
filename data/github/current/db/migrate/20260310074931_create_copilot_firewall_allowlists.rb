# typed: true
# frozen_string_literal: true

# Migration to create copilot_firewall_allowlists table.
#
# See: https://github.com/github/sweagentd/issues/10536
class CreateCopilotFirewallAllowlists < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_firewall_allowlists, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :organization_id, unsigned: true, comment: "Denormalized org ID for efficient queries"
      t.string :resource_type, null: false, limit: 50, comment: "Business, Organization, or Repository"
      t.bigint :resource_id, null: false, comment: "The entity that owns this allowlist", unsigned: true
      t.column :rules, :json, null: false, default: -> { "(JSON_ARRAY())" }, comment: "JSON array of allowlist rules (domains, IPs, URLs)"
      t.bigint :updated_by_id, null: false, unsigned: true, comment: "The user who last updated the record"
      t.timestamps

      # rubocop:disable GitHub/AvoidTypeBeforeId
      t.index [:resource_type, :resource_id], unique: true, name: "index_copilot_firewall_allowlists_on_resource"
      # rubocop:enable GitHub/AvoidTypeBeforeId
      t.index [:organization_id], name: "index_copilot_firewall_allowlists_on_org_id"
    end
  end
end
