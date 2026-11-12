# frozen_string_literal: true

class IndexToStateOnUpdateJobTransitions < ActiveRecord::Migration[6.0]
  def change
    add_index :update_job_transitions, %i(most_recent to_state)
  end
end
