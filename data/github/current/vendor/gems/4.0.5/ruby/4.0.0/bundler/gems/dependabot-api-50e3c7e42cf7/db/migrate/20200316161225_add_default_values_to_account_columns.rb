# frozen_string_literal: true

class AddDefaultValuesToAccountColumns < ActiveRecord::Migration[6.0]
  def change # rubocop:disable Metrics/MethodLength
    change_column_default(
      :accounts,
      :weekly_update_run_day,
      from: nil,
      to: "monday"
    )
    change_column_default(:accounts, :update_run_time, from: nil, to: "05:00")
    change_column_default(:accounts, :timezone, from: nil, to: "UTC")
    change_column_default(:accounts, :branch_name_separator, from: nil, to: "/")
    change_column_default(
      :accounts,
      :open_pull_requests_limit,
      from: nil,
      to: 5
    )
    change_column_default(
      :accounts,
      :automatically_rebase_prs,
      from: nil,
      to: true
    )
    change_column_default(
      :accounts,
      :only_automerge_during_working_hours,
      from: nil,
      to: false
    )
    change_column(:accounts, :automerge_working_hours, :text, null: true) # rubocop:disable Rails/ReversibleMigration
  end
end
