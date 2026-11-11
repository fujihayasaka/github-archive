# frozen_string_literal: true

class IndexAccountOnGitHubLogin < ActiveRecord::Migration[6.0]
  def change
    add_index :accounts, :github_login
  end
end
