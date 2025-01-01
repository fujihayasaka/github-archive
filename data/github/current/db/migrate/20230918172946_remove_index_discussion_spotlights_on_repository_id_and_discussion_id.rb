# typed: strict
class RemoveIndexDiscussionSpotlightsOnRepositoryIdAndDiscussionId < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  sig { void }
  def change
    remove_index :discussion_spotlights, column: [:repository_id, :discussion_id], name: "index_discussion_spotlights_on_repository_id_and_discussion_id", unique: true
  end
end
