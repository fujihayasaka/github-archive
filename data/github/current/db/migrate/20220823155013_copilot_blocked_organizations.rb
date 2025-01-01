# typed: true
class CopilotBlockedOrganizations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_blocked_organizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :organization_id, unsigned: true, null: false, index: { unique: true }, comment: "The organization"
      t.timestamps
    end
  end
end
