# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NetworkOwner < Platform::Loader
      def self.load(network_id)
        self.for.load(network_id)
      end

      def self.load_all(network_ids)
        loader = self.for
        Promise.all(network_ids.map { |network_id| loader.load(network_id) })
      end

      def fetch(network_ids)
        Repositories.domain.networks.owners_by_ids(network_ids)
      end
    end
  end
end
