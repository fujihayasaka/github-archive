# frozen_string_literal: true

class IndexUpdateConfigLastUpdateRun < ActiveRecord::Migration[6.0]
  def change
    add_index :update_jobs,
              %i(update_config_id pull_request_transition_id),
              name: "index_update_jobs_on_update_config_id_and_pr_transition_id"
  end
end
