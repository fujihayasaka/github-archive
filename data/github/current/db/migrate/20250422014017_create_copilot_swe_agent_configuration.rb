# typed: true

class CreateCopilotSweAgentConfiguration < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_swe_agent_configuration, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Start with a polymorphic association to the resource. This will be the repository or organization that owns this exclusion document.
      # We start with this to make sure that we can use the same table for both repositories and organizations.
      t.references :resource, polymorphic: true, index: { unique: true }, null: false, comment: "The repository or organization that owns this configuration"
      # Blob here implies a max size of 65KB. This seems reasonable, it sounds like the DB team is resistant to using mediumblob
      # so we would need to use ABS if we want to go higher.
      t.blob :mcp_configuration, default: nil, index: false, comment: "The mcp configuration document"
      t.bigint :updated_by_id, unsigned: true, index: false, null: true, comment: "The user who last updated the record"
      t.timestamps
    end
  end
end
