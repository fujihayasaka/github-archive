# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddIndexToDeploymentsOnCheckRunIdRepositoryIdCreatedAt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_index :deployments, [:check_run_id, :repository_id, :created_at],
      name: :index_check_run_id_repository_id_created_at, unique: false
  end
end
