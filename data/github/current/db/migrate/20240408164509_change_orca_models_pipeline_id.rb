class ChangeOrcaModelsPipelineId < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :orca_models, bulk: true do |t|
      t.remove_references :orca_pipeline_request,
        index: { unique: true }

      t.string :pipeline_id, null: false
    end
  end
end
