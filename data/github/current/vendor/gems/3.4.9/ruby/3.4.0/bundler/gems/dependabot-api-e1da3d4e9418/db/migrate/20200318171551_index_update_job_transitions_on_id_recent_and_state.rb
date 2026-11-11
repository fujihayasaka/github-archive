# frozen_string_literal: true

class IndexUpdateJobTransitionsOnIdRecentAndState < ActiveRecord::Migration[6.0]
  def change
    add_index :update_job_transitions,
              %i(update_job_id most_recent to_state),
              name: "index_per_job_most_recent_and_state"
  end
end
