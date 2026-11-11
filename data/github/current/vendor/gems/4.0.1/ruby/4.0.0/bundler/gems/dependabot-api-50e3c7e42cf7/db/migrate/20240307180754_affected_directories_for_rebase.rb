# frozen_string_literal: true

class AffectedDirectoriesForRebase < ActiveRecord::Migration[7.0]
  def change
    add_column :pull_requests, :affected_directories, :text
    add_column :update_jobs, :directories, :text
  end
end
