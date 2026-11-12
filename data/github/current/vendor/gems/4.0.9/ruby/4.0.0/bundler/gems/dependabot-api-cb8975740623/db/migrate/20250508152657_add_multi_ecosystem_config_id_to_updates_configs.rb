# frozen_string_literal: true

class AddMultiEcosystemConfigIdToUpdatesConfigs < ActiveRecord::Migration[7.0]
  def change
    change_table :update_configs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.bigint :multi_ecosystem_config_id, unsigned: true, null: true
      t.index :multi_ecosystem_config_id
    end
  end
end
