# frozen_string_literal: true

class AddUpdateConfigIdToPullRequestsTable < ActiveRecord::Migration[6.0]
  def change
    add_column :pull_requests, :update_config_id, :bigint
  end
end
