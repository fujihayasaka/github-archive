# frozen_string_literal: true

class AddDirectoriesToUpdateConfigs < ActiveRecord::Migration[7.0]
  def change
    add_column :update_configs, :directories, :text
  end
end
