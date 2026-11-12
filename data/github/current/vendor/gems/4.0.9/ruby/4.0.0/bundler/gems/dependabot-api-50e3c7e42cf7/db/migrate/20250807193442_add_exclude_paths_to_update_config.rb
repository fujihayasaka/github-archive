# frozen_string_literal: true

class AddExcludePathsToUpdateConfig < ActiveRecord::Migration[7.0]
  def change
    add_column :update_configs, :exclude_paths, :text
  end
end
