# typed: true
# frozen_string_literal: true

class IndexRestorableCustomWatchedRepositoriesOnRestorableIdAndUserId < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::Restorables)

  def up
    change_table(:restorable_custom_watched_repositories, bulk: true) do |t|
      t.index [:restorable_id, :user_id], name: "idx_restorable_cwrs_on_restorable_id_and_user_id"
      t.remove_index name: "index_restorable_custom_watched_repositories_on_restorable_id"
    end
  end

  def down
    change_table(:restorable_custom_watched_repositories, bulk: true) do |t|
      t.index [:restorable_id], name: "index_restorable_custom_watched_repositories_on_restorable_id"
      t.remove_index name: "idx_restorable_cwrs_on_restorable_id_and_user_id"
    end
  end
end
