# typed: true

class AddRepoIdIndexToPullRequestOrchestrations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_request_orchestrations, bulk: true do |t|
      t.index [:repository_id, :pull_request_id, :type, :state], name: "index_pr_orchestrations_on_repo_id_pull_id_type_state"
    end
  end
end
