# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class RepositoryNetworks < GH::Domain::Base
      decorate_with GH::Decorator::TestBedIdCaching, only: [:by_id]

      # Get a network by ID
      sig { params(id: Integer).returns(T.nilable(Repositories::IRepositoryNetwork)).checked(:always).on_failure(:raise) }
      def by_id(id)
        ::RepositoryNetwork.find_by(id: id)
      end

      # Get a networks by IDs
      sig { params(ids: T::Array[T.nilable(Integer)]).returns(T::Array[Repositories::IRepositoryNetwork]) }
      def by_ids(ids)
        ::RepositoryNetwork.where(id: ids).to_a
      end

      # Returns a hash of network IDs to their owners
      sig { params(network_ids: T::Array[Integer]).returns(T::Hash[Integer, Users::IUser]) }
      def owners_by_ids(network_ids)
        results = Repository.connection.select_rows(Arel.sql(<<-SQL, network_ids: network_ids))
          SELECT network.id AS network_id, root.owner_id AS owner_id
          FROM repositories root
          JOIN repository_networks network ON root.id = network.root_id
          WHERE network.id IN (:network_ids)
        SQL

        owner_ids = results.map { |_, owner_id| owner_id }.uniq
        owners_by_id = Users.domain.by_ids(owner_ids).index_by(&:id)

        results.each_with_object({}) do |(network_id, owner_id), by_network|
          by_network[network_id] = owners_by_id[owner_id] if owners_by_id[owner_id]
        end
      end

      # Get a fork in the network for a user
      sig { params(repo: ::Repositories::IRepository, head_owner: String).returns(T.nilable(::Repositories::IRepository)) }
      def find_fork_in_network_for_user(repo, head_owner)
        T.cast(repo, Repository).find_fork_in_network_for_user(head_owner) # rubocop:todo GitHub/AvoidCast
      end
    end
  end
end
