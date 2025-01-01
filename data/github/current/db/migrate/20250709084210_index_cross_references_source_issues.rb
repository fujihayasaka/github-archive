# typed: true
# frozen_string_literal: true

class IndexCrossReferencesSourceIssues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :cross_references, bulk: true do |t|
      t.index [:target_type, :target_id, :source_type, :target_repository_id, :user_hidden, :source_repository_id, :source_id, :actor_id, :created_at], name:  "index_cross_references_on_source_issues"
    end
  end
end
