# typed: true
# frozen_string_literal: true

class DropPrIdRepoIdTypeStateIndexOnPullRequestOrchestrations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def up
    change_table :pull_request_orchestrations, bulk: true do |t|
      t.remove_index name: "index_pull_orchestrations_on_pull_id_repository_id_type_state"
    end
  end

  def down
    change_table :pull_request_orchestrations, bulk: true do |t|
      t.index [:pull_request_id, :repository_id, :type, :state], name: "index_pull_orchestrations_on_pull_id_repository_id_type_state"
    end
  end
end
