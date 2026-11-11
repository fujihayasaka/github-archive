# frozen_string_literal: true

class ReduceCurrentStateColumnLength < ActiveRecord::Migration[7.2]
  def up
    change_column :update_configs, :current_state, :string, limit: 40, null: true
    change_column :update_jobs, :current_state, :string, limit: 40, null: true
    change_column :accounts, :current_state, :string, limit: 40, null: true
    change_column :pull_requests, :current_state, :string, limit: 40, null: true
    change_column :pending_pull_requests, :current_state, :string, limit: 40, null: true
  end

  def down
    change_column :update_configs, :current_state, :string, limit: 255, null: true
    change_column :update_jobs, :current_state, :string, limit: 255, null: true
    change_column :accounts, :current_state, :string, limit: 255, null: true
    change_column :pull_requests, :current_state, :string, limit: 255, null: true
    change_column :pending_pull_requests, :current_state, :string, limit: 255, null: true
  end
end
