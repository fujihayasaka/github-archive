# typed: true
# frozen_string_literal: true

class AddIndexOnStateAndNetworkIdToColdNetworks < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def change
    add_index :cold_networks, [:state, :network_id], if_not_exists: true
  end
end
