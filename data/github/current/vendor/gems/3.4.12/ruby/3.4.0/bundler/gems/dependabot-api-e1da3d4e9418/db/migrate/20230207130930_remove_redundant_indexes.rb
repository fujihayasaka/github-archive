# frozen_string_literal: true

class RemoveRedundantIndexes < ActiveRecord::Migration[7.0]
  def change
    remove_index :pending_pull_requests, :update_job_id
    remove_index :update_configs, :repo_id, name: "fk_rails_c022fe45cb"
  end
end
