# frozen_string_literal: true

class RemoveAccountsCanAccessAllRepos < ActiveRecord::Migration[6.0]
  def change
    remove_column :accounts, :can_access_all_repos, :boolean, null: false
  end
end
