# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
# justification: we do not have business teams entries in production yet, this is a new feature and we forgot to add the key

class AddUniqueKeyToTeamsOnBusinessAndSlug < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :teams, bulk: true do |t|
      t.index [:business_id, :slug], unique: true
      t.remove_index :business_id
    end
  end
end
