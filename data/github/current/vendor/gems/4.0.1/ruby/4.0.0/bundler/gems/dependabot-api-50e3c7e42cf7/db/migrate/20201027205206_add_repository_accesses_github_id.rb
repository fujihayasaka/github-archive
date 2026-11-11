# frozen_string_literal: true

class AddRepositoryAccessesGitHubId < ActiveRecord::Migration[6.0]
  def change
    add_index :repository_accesses, %i(account_id github_id), unique: true
  end
end
