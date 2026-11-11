# frozen_string_literal: true

class AddEnableBetaEcosystemsToUpdateConfigs < ActiveRecord::Migration[7.0]
  def change
    add_column :update_configs, :enable_beta_ecosystems, :boolean, default: false, null: false
  end
end
