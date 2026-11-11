# frozen_string_literal: true

class AlterGhsaUniquenessIndexes < ActiveRecord::Migration[6.0]
  def change
    remove_index :github_security_advisories, :ghsa_id

    add_index :github_security_advisories,
              %i(ghsa_id package_manager dependency_name),
              name: :index_ghsa_dependency,
              unique: true
  end
end
