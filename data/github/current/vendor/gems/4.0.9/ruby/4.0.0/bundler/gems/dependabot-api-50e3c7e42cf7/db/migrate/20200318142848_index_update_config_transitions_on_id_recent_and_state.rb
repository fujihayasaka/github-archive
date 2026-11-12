# frozen_string_literal: true

class IndexUpdateConfigTransitionsOnIdRecentAndState < ActiveRecord::Migration[6.0]
  def change
    add_index :update_config_transitions,
              %i(update_config_id most_recent to_state),
              name: "index_per_config_most_recent_and_state"
  end
end
