# typed: true
# frozen_string_literal: true

class CreateIntegrationInstallationAgentConsents < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :integration_installation_agent_consents, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :integration_installation_id, :bigint, unsigned: true, null: false
      t.index  :integration_installation_id, unique: true

      t.column :integration_agent_source_id, :bigint, unsigned: true, null: false
      t.index  :integration_agent_source_id

      t.column :approver_id, :bigint, unsigned: true, null: false
      t.column :approved_at, "datetime(6)", null: false

      t.timestamps
    end
  end
end
