# frozen_string_literal: true

# Migration to add current_state columns to tables with state machines,
# for making state queries more efficient.  Indexes are added to each table
# as needed to optimize common queries filtering by current_state.
# The indexes need to reference current_state before the association
# id to avoid inefficient range scans on aggregated states (e.g., pull requests
# are "open" when they're either "up_to_date" or "updating", and update jobs
# are "completed" when they're in one of many terminal states).
class AddCurrentStates < ActiveRecord::Migration[7.1]
  def change
    change_table :update_configs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :current_state, null: true
      t.index %i(current_state repo_id)
    end

    change_table :update_jobs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :current_state, null: true
      t.index %i(current_state update_config_id)
    end

    change_table :pull_requests, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :current_state, null: true

      # Creating indexes separately for repo and update config
      # associations is necessary to avoid range queries that inefficiently
      # scan the entire table.
      t.index %i(current_state update_config_id)
      t.index %i(current_state repo_id)
    end

    change_table :pending_pull_requests, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :current_state, null: true
      t.index %i(current_state update_job_id)
    end

    change_table :accounts, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :current_state, null: true

      # At this point in time, dependabot-api doesn't ever query accounts by
      # current_state, so we don't add an index here.
    end
  end
end
