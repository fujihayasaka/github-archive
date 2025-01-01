# typed: true
# frozen_string_literal: true

module GitHub
  class MediaBlob
    STARTER  = 0
    SAVED    = 1
    DELETED  = 2
    VERIFIED = 3
    ARCHIVED = 4

    # A few networks have an exceptionally large number of LFS objects which cause
    # query timeouts in `def query_network_storage`.  Avoid the timeouts by
    # processing these networks individually if they are known.
    #
    # Currently only network 222237031 with >9 million LFS objects is causing timeouts.
    # To avoid timeouts for other networks in the near future, we process all networks
    # with currently more than 2 million LFS objects individually.
    LARGE_NETWORKS = Set.new([
      222237031,
      255507415,
      387641078,
      482148593,
      528450823,
      584405238
      ]).freeze

    # Gets a list of LFS media blob object IDs and corresponding repository
    # network IDs, up to the given limit, and optionally constrained to those
    # with primary IDs between offset and next_offset.
    def self.get_object_repository_networks(offset, next_offset, limit)
      sql = Arel.sql(<<-SQL, verified: VERIFIED, archived: ARCHIVED)
        SELECT id, oid, repository_network_id
          FROM media_blobs
         WHERE state IN (:verified, :archived)
      SQL

      if offset && next_offset
        sql += Arel.sql "AND id BETWEEN :offset AND :next_offset", offset: offset, next_offset: next_offset
      end

      sql += Arel.sql "LIMIT :limit", limit: Arel.sql(limit.to_s)

      ApplicationRecord::Domain::Assets.connection.select_rows(sql)
    end

    # Returns an array hashes containing the owner, network ID, and LFS storage
    # size of a network. The query is constrained to repository networks with
    # IDs larger than `prev_batch_id` and the given limit to results.
    def self.query_owner_network_storage(prev_batch_id, limit)
      network_ids = self.query_networks(prev_batch_id, limit)

      # If a batch is smaller than the batch size, then we have reached the end
      # Note, if the batch equals the batch size then we cannot tell if there is
      # more data. A subsequent fetch might return zero results.
      is_last_batch = network_ids.size < limit

      # Reject a network with a disabaled repository that has 33 million Git LFS blobs
      # see https://github.com/github/git-systems/issues/1784
      network_ids.reject! { |id| id == 312840998 }

      # Get the last network ID of the current batch to define the beginning of
      # the next batch.
      last_network_id = network_ids.last

      # Query the used LFS storage per network. Process known large networks individually.
      network_with_lfs = self.query_network_storage(network_ids.reject { |id| id.in?(LARGE_NETWORKS) })
      LARGE_NETWORKS.each do |nw|
        network_with_lfs += self.query_network_storage([nw]) if nw.in?(network_ids)
      end

      network_with_root_and_owner = self.query_network_owner(network_ids)

      results = network_with_lfs.filter_map do |entry|
        nw_id = entry.first
        # Calculate the size in GiB with byte precision
        size_in_gb = (entry.second / (1024**3)).floor(9)
        root_and_owner = network_with_root_and_owner.fetch(nw_id, {})
        owner = root_and_owner[:owner]
        # Currently, we have lots of networks without an owner. Do we want to emit an error in that case?
        if owner
          actor = owner.delegate_billing_to_business? ? owner.business : owner
          {
            owner_id: owner.id,
            customer_id: GitHub.flipper[:lfs_metered_billing_vnext].enabled?(actor) ? Asset::Activity.fetch_or_create_customer_id(owner) : 0,
            network_id: nw_id,
            business_id: owner.delegate_billing_to_business? ? owner.business.id : nil,
            organization_id: owner.is_a?(Organization) ? owner.id : nil,
            root_id: root_and_owner[:root_id],
            size_in_gb: size_in_gb,
          }
        end
      end

      [results, is_last_batch, last_network_id]
    end

    # Returns a hash of "network ID => root id, owner object" entities
    def self.query_network_owner(network_ids)
      network_with_owner_id = RepositoryNetwork.joins(:root).where(id: network_ids).pluck(:id, :root_id, "repositories.owner_id")
      owner_ids = network_with_owner_id.map { |e| e.third }
      owners = User.where(id: owner_ids).inject({}) { |hash, e| hash[e.id] = e; hash }
      network_with_owner_id.inject({}) { |hash, e| hash[e.first] = { root_id: e.second, owner: owners[e.third] }; hash }
    end

    def self.query_networks(prev_batch_id, limit)
      prev_batch_id = -1 if prev_batch_id.nil?
      sql = Arel.sql(<<-SQL, prev_batch_id: prev_batch_id, limit: Arel.sql(limit.to_s))
        SELECT DISTINCT(repository_network_id)
        FROM media_blobs
        WHERE repository_network_id > :prev_batch_id
        ORDER BY repository_network_id ASC
        LIMIT :limit
      SQL
      ApplicationRecord::Domain::Assets.connection.select_rows(sql).flatten
    end

    # Returns an array of "network ID, used LFS storage in network" arrays.
    # A batch of 1,000 networks takes ~2 seconds to run and we have currently
    # 1,000,000 networks.
    def self.query_network_storage(network_ids)
      return [] if network_ids.empty?
      sql = Arel.sql(<<-SQL, verified: VERIFIED, network_ids: network_ids)
        SELECT repository_network_id, SUM(size)
        FROM media_blobs
        WHERE state = :verified AND repository_network_id IN (:network_ids)
        GROUP BY repository_network_id
      SQL
      ApplicationRecord::Domain::Assets.connection.select_rows(sql)
    end
  end
end
