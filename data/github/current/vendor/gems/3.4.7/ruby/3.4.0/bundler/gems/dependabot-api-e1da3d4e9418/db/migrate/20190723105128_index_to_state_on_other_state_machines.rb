# frozen_string_literal: true

class IndexToStateOnOtherStateMachines < ActiveRecord::Migration[6.0]
  # rubocop:disable Metrics/MethodLength
  def change
    add_index(
      :update_config_transitions,
      %i(most_recent to_state)
    )

    add_index(
      :pull_request_transitions,
      %i(most_recent to_state)
    )

    add_index(
      :account_transitions,
      %i(most_recent to_state)
    )

    add_index(
      :issue_transitions,
      %i(most_recent to_state)
    )

    add_index(
      :pending_pull_request_transitions,
      %i(most_recent to_state),
      name: "index_pending_prs_on_most_recent_and_to_state"
    )
  end
  # rubocop:enable Metrics/MethodLength
end
