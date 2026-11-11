# typed: true
# frozen_string_literal: true

class CreateIntegrationAgentSources < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :integration_agent_sources, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :integration_id, :bigint, unsigned: true, null: false
      t.index  :integration_id, unique: true

      t.column :repository_id, :bigint, unsigned: true, null: false
      t.index  :repository_id

      t.column :commit_oid, "varchar(64)", null: false # Support for SHA1 and SHA256 OIDs

      t.timestamps
    end
  end
end
