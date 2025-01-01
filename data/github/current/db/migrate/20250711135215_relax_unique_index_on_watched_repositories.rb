# typed: true
# frozen_string_literal: true

class RelaxUniqueIndexOnWatchedRepositories < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::Restorables)

  def up
    change_table(:restorable_watched_repositories, bulk: true) do |t|
      t.index [:restorable_id, :repository_id]
      t.remove_index name: "index_restorable_watched_repositories"
    end
  end

  def down
    change_table(:restorable_watched_repositories, bulk: true) do |t|
      t.index [:restorable_id, :repository_id], unique: true, name: "index_restorable_watched_repositories"
      t.remove_index [:restorable_id, :repository_id]
    end
  end
end
