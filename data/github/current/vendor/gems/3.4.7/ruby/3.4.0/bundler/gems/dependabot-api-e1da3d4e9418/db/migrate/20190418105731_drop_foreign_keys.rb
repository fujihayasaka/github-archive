# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
class DropForeignKeys < ActiveRecord::Migration[6.0]
  def change
    remove_foreign_key :account_transitions, :accounts
    remove_foreign_key :config_file_errors, :repos
    remove_foreign_key :config_variables, :accounts
    remove_foreign_key :ignore_conditions, :update_configs
    remove_foreign_key :issue_transitions, :issues
    remove_foreign_key :issues, :repos
    remove_foreign_key :issues, :update_jobs
    remove_foreign_key :pending_pull_request_transitions, :pending_pull_requests
    remove_foreign_key :pending_pull_requests, :update_jobs
    remove_foreign_key :pull_request_transitions, :update_jobs
    remove_foreign_key :pull_request_transitions, :pull_requests
    remove_foreign_key :pull_requests, :repos
    remove_foreign_key :pull_requests, :update_jobs
    remove_foreign_key :repos, :accounts
    remove_foreign_key :update_config_transitions, :update_configs
    remove_foreign_key :update_configs, :repos
    remove_foreign_key :update_job_errors, :update_jobs
    remove_foreign_key :update_job_transitions, :update_jobs
    remove_foreign_key :update_jobs, :pull_request_transitions
    remove_foreign_key :update_jobs, :update_configs
    remove_foreign_key :updated_dependencies, :pull_requests
  end
end
# rubocop:enable Metrics/MethodLength
