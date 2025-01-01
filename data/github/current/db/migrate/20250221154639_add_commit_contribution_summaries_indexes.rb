# typed: true
# frozen_string_literal: true

class AddCommitContributionSummariesIndexes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :commit_contribution_summaries, bulk: true do |t|
      t.index [:repository_id, :year], name: "index_commit_contribution_summaries_on_repo_id_year"
      t.index [:user_id, :year], name: "index_commit_contribution_summaries_on_user_id_year"
      t.remove_index name: "index_commit_contribution_summaries_on_repository_id"
    end
  end

  def down
    change_table :commit_contribution_summaries, bulk: true do |t|
      t.index [:repository_id], name: "index_commit_contribution_summaries_on_repository_id"
      t.remove_index name: "index_commit_contribution_summaries_on_repo_id_year"
      t.remove_index name: "index_commit_contribution_summaries_on_user_id_year"
    end
  end
end
