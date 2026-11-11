# frozen_string_literal: true

class ChangePendingPullRequestsUpdatedDependencyDetailsSize < ActiveRecord::Migration[6.0]
  def change
    change_column :pending_pull_requests, :updated_dependency_details, :mediumtext # rubocop:disable Rails/ReversibleMigration
  end
end
