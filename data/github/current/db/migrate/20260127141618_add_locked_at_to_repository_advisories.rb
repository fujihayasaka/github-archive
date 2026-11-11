# typed: true
# frozen_string_literal: true

class AddLockedAtToRepositoryAdvisories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    add_column :repository_advisories, :locked_at, :datetime, precision: 6, null: true
  end
end
