# typed: true

class AddPipelineGroupIdToCopilotOrcaModels < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Copilot

  def change
    change_table :orca_models, bulk: true do |t|
      t.references :pipeline_group,
        type: :bigint,
        unsigned: true,
        null: true,
        index: { unique: false }
    end
  end
end
