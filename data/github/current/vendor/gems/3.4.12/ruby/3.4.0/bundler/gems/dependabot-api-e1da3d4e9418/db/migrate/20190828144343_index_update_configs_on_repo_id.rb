# frozen_string_literal: true

class IndexUpdateConfigsOnRepoId < ActiveRecord::Migration[6.0]
  def change
    add_index :update_configs, :repo_id
  end
end
