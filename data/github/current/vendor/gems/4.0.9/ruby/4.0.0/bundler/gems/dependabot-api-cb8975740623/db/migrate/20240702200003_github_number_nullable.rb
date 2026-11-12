# frozen_string_literal: true

class GitHubNumberNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null(:pull_requests, :github_number, true)
  end
end
