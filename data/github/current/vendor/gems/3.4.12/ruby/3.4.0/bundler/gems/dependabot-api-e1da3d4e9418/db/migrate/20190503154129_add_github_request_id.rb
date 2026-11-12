# frozen_string_literal: true

class AddGitHubRequestId < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :github_request_id, :integer, null: true
  end
end
