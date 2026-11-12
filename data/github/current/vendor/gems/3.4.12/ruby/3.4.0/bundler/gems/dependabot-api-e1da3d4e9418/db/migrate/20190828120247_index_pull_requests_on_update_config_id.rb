# frozen_string_literal: true

class IndexPullRequestsOnUpdateConfigId < ActiveRecord::Migration[6.0]
  def change
    add_index :pull_requests, :update_config_id
  end
end
