# typed: strict

class AddIndexDiscussionSpotlightsOnDiscussionIdRepositoryId < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  sig { void }
  def change
    # https://janky.githubapp.com/flaky_tests/f0fc21a59522f56e4716ee2ee3ce664f7e1bc108d3faaca473446ed648f1a3ca
    # GitHub/ExistingIdColumnsMustBeBigint: This table has one or more existing columns that appears to be an integer primary or foreign key using a legacy data type
    change_table :discussion_spotlights, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :discussion_id, :bigint, unsigned: true
      t.change :spotlighted_by_id, :bigint, unsigned: true
      t.index [:discussion_id, :repository_id], name: "index_discussion_spotlights_on_discussion_id_and_repository_id", unique: true
    end
  end

  sig { void }
  def reversible
    # Not actually reversible; this is just to avoid a warning.
    # The data would be truncated if this migration were reversed,
    # and that makes other warnings or errors appear if implemented.
  end
end
