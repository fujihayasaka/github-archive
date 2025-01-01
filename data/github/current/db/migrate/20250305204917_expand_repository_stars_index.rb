# typed: true
# frozen_string_literal: true

class ExpandRepositoryStarsIndex < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::Restorables)

  def up
    change_table(:restorable_repository_stars, bulk: true) do |t|
      t.index [:restorable_id, :repository_id]
      t.remove_index name: "index_restorable_repository_stars"
    end
  end

  def down
    change_table(:restorable_repository_stars, bulk: true) do |t|
      t.index [:restorable_id, :repository_id], unique: true, name: "index_restorable_repository_stars"
      t.remove_index [:restorable_id, :repository_id]
    end
  end
end
