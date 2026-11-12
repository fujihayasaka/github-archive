# frozen_string_literal: true

class AddAccountRepositoryAccessLevel < ActiveRecord::Migration[6.0]
  def change
    add_column :accounts, :repository_access_level,
               "enum('public_repos', 'all_repos', 'selected_private_repos')",
               null: false,
               default: "public_repos"
  end
end
