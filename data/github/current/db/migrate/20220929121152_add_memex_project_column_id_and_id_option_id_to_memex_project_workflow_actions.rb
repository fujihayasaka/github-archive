# typed: true

class AddMemexProjectColumnIdAndIdOptionIdToMemexProjectWorkflowActions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Memex)

  def change
    change_table :memex_project_workflow_actions, bulk: true do |t|
      t.virtual :memex_project_column_id, type: :bigint, unsigned: true, as: "(`arguments` ->> '$.fieldId')"
      t.virtual :option_id, limit: 8, type: :string, as: "(`arguments` ->> '$.fieldOptionId')"

      t.index [:memex_project_column_id, :option_id, :action_type],
        name: "index_mpwa_on_mpc_id_option_id_and_action_type"
    end
  end
end
