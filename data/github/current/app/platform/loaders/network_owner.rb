# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NetworkOwner < Platform::Loader
      def self.load(network_id)
        self.for.load(network_id)
      end

      def fetch(network_ids)
        results = Repository.connection.select_rows(Arel.sql(<<-SQL, network_ids: network_ids))
          SELECT network.id AS network_id, root.owner_id AS owner_id
          FROM repositories root
          JOIN repository_networks network ON root.id = network.root_id
          WHERE network.id IN (:network_ids)
        SQL

        owner_ids = results.map { |_, owner_id| owner_id }.uniq
        owners_by_id = User.where(id: owner_ids).index_by(&:id)

        results.each_with_object({}) do |(network_id, owner_id), by_network|
          by_network[network_id] = owners_by_id[owner_id] if owners_by_id[owner_id]
        end
      end
    end
  end
end
