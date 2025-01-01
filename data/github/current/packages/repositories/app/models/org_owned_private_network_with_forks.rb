# typed: true
# frozen_string_literal: true

class OrgOwnedPrivateNetworkWithForks < ApplicationRecord::Domain::Repositories
  self.table_name = "org_owned_private_networks_with_forks"

  def self.destroy_by_network_id(network_id)
    find_by(network_id: network_id)&.destroy
  end
end
