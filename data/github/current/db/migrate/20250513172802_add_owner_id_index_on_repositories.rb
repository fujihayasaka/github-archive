# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddOwnerIdIndexOnRepositories < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :repositories, bulk: true do |t|
      t.remove_index column: [:disabled_at], name: "index_repositories_on_disabled_at"

      t.index [:owner_id], name: "index_repositories_on_owner_id"
    end
  end
end
