# frozen_string_literal: true

class IndexPendingPullRequestOnCreatedAt < ActiveRecord::Migration[6.0]
  def change
    add_index :pending_pull_requests, :created_at
  end
end
