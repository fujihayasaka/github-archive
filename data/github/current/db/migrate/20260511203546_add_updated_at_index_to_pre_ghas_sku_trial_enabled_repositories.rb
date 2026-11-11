# typed: true
# frozen_string_literal: true

class AddUpdatedAtIndexToPreGhasSKUTrialEnabledRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class ApplicationRecord::Domain::SecurityProductsEnablement

  def change
    add_index :pre_ghas_sku_trial_enabled_repositories, :updated_at, name: "index_pre_ghas_sku_trial_enabled_repositories_on_updated_at"
  end
end
