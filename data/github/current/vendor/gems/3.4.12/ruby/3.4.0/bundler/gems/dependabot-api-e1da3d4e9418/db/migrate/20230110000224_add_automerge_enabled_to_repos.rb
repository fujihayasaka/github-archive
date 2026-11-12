# frozen_string_literal: true

class AddAutomergeEnabledToRepos < ActiveRecord::Migration[7.0]
  def change
    add_column :repos, :automerge_enabled, :boolean
  end
end
