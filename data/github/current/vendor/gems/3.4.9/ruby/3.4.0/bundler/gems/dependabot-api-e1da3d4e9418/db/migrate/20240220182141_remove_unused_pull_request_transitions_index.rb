# frozen_string_literal: true

class RemoveUnusedPullRequestTransitionsIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index(
      :pull_request_transitions,
      %w(most_recent to_state),
      name: "index_pull_request_transitions_on_most_recent_and_to_state"
    )
  end
end
