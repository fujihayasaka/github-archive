# frozen_string_literal: true

class AlterUpdateJobsGitHubRequestIdSize < ActiveRecord::Migration[6.0]
  def up
    change_column :update_jobs, :github_request_id, :bigint, unsigned: true, null: true
  end

  def down
    change_column :update_jobs, :github_request_id, :integer, null: true
  end
end
