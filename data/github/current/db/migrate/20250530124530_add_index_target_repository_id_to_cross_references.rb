# typed: true

class AddIndexTargetRepositoryIdToCrossReferences < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :cross_references, bulk: true do |t|
      t.index [:target_id, :target_repository_id, :target_type, :source_type], name:  "index_cross_references_on_target_id_and_target_repository_id"
    end
  end
end
