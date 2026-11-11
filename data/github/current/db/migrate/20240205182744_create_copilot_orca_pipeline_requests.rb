class CreateCopilotOrcaPipelineRequests < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :orca_pipeline_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: false }

      t.references :user,
        type: :bigint,
        unsigned: true,
        null: false

      t.json :repository_ids,
        null: false

      t.json :file_extensions,
        null: false

      t.string :pipeline_id,
        limit: 36,
        null: true,
        index: { unique: true }

      t.timestamps
    end
  end
end
