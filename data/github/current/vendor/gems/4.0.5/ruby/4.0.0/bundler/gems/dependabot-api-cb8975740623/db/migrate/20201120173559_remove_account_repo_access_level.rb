# frozen_string_literal: true

class RemoveAccountRepoAccessLevel < ActiveRecord::Migration[6.0]
  def change
    remove_column :accounts, :repository_access_level,
                  "enum('public_repos', 'all_repos', 'selected_private_repos')",
                  null: false,
                  default: "public_repos"
  end
end
