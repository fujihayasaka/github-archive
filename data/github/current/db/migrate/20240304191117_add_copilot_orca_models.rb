class AddCopilotOrcaModels < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :orca_models, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: false }

      t.references :orca_pipeline_request,
        type: :bigint,
        unsigned: true,
        null: false,
        index: { unique: true }

      t.string :resource,
        null: false

      t.string :deployment,
        null: false

      t.timestamps
    end
  end
end
