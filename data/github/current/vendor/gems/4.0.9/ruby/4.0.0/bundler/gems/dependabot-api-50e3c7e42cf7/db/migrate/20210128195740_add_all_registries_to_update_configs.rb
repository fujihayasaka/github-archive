# frozen_string_literal: true

class AddAllRegistriesToUpdateConfigs < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :all_registries, :boolean, default: false
  end
end
