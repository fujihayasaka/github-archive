# frozen_string_literal: true

class IndexGitHubFieldsOnUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_index :update_jobs, :github_request_id
    add_index :update_jobs, :trigger_type
  end
end
