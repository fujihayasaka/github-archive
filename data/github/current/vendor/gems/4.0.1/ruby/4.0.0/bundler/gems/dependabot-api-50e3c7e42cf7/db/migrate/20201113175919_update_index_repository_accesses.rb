# frozen_string_literal: true

class UpdateIndexRepositoryAccesses < ActiveRecord::Migration[6.0]
  def change
    remove_index :repository_accesses, %i(account_id github_id)
    add_index :repository_accesses, :account_id
    add_index :repository_accesses, :github_id, unique: true
  end
end
