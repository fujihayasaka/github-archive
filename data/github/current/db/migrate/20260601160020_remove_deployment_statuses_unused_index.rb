# rubocop:disable GitHub/ArchivedTable
# typed: true
# frozen_string_literal: true

class RemoveDeploymentStatusesUnusedIndex < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :deployment_statuses, bulk: true do |t|
      t.remove_index name: :index_deployment_statuses_on_environment_id
    end
  end

  def down
    change_table :deployment_statuses, bulk: true do |t|
      t.index [:environment_id], name: :index_deployment_statuses_on_environment_id
    end
  end
end

# rubocop:enable GitHub/ArchivedTable
