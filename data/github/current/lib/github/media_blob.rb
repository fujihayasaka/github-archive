# typed: true
# frozen_string_literal: true

module GitHub
  class MediaBlob
    STARTER  = 0
    SAVED    = 1
    DELETED  = 2
    VERIFIED = 3
    ARCHIVED = 4

    STORAGE_SUM_BLOB_BATCH_SIZE = 1000

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

    # Returns an array of hashes containing the owner, network ID, and LFS storage
    # size of a network. The query is constrained to repository networks with
    # IDs larger than `prev_batch_id` and the given limit to results.
    def self.query_owner_network_storage(prev_batch_id, limit)
      network_ids = self.query_networks(prev_batch_id, limit)

      # If a batch is smaller than the batch size, then we have reached the end
      # Note, if the batch equals the batch size then we cannot tell if there is
      # more data. A subsequent fetch might return zero results.
      is_last_batch = network_ids.size < limit

      unless ::FeatureFlag.vexi.enabled?("lfs_storage_by_networks_query_tuning", default: false)
        # Reject a network with a disabaled repository that has 33 million Git LFS blobs
        # see https://github.com/github/git-systems/issues/1784
        network_ids.reject! { |id| id == 312840998 }
      end

      # Get the last network ID of the current batch to define the beginning of
      # the next batch.
      last_network_id = network_ids.last

      if ::FeatureFlag.vexi.enabled?("lfs_storage_by_networks_query_tuning", default: false)
        # Query the used LFS storage per network.
        network_with_lfs = self.query_network_storage(network_ids)
      else
        # Query the used LFS storage per network. Process known large networks individually.
        network_with_lfs = self.query_network_storage(network_ids.reject { |id| id.in?(LARGE_NETWORKS) })
        LARGE_NETWORKS.each do |nw|
          network_with_lfs += self.query_network_storage([nw]) if nw.in?(network_ids)
        end
      end

      network_with_root_and_owner = self.query_network_owner(network_ids)

      if ::FeatureFlag.vexi.enabled?("lfs_storage_by_networks_query_tuning", default: false)
        results = network_with_lfs.map do |nw_id, usage|
          # Calculate the size in GiB with byte precision
          size_in_gb = (usage / (1024**3)).floor(9)
          root_and_owner = network_with_root_and_owner.fetch(nw_id, {})
          owner = root_and_owner[:owner]
          # Currently, we have lots of networks without an owner. Do we want to emit an error in that case?
          if owner
            actor = owner.delegate_billing_to_business? ? owner.business : owner
            {
              owner_id: owner.id,
              customer_id: owner.feature_enabled?(:use_find_or_create_customer) ? owner.find_or_create_customer.id : (actor.customer&.id || 0),
              network_id: nw_id,
              business_id: owner.delegate_billing_to_business? ? owner.business.id : nil,
              organization_id: owner.is_a?(Organization) ? owner.id : nil,
              root_id: root_and_owner[:root_id],
              size_in_gb: size_in_gb,
            }
          end
        end
      else
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
              customer_id: owner.feature_enabled?(:use_find_or_create_customer) ? owner.find_or_create_customer.id : (actor.customer&.id || 0),
              network_id: nw_id,
              business_id: owner.delegate_billing_to_business? ? owner.business.id : nil,
              organization_id: owner.is_a?(Organization) ? owner.id : nil,
              root_id: root_and_owner[:root_id],
              size_in_gb: size_in_gb,
            }
          end
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

    # Returns a hash of "network ID => used LFS storage in network" entries
    # when "lfs_storage_by_networks_query_tuning" is enabled.  Otherwise,
    # returns an array of "network ID, used LFS storage in network" arrays.
    # A batch of 1,000 networks takes ~2 seconds to run and we have currently
    # 1,000,000 networks.
    def self.query_network_storage(network_ids, blob_batch_size: STORAGE_SUM_BLOB_BATCH_SIZE)
      return [] if network_ids.empty?

      if ::FeatureFlag.vexi.enabled?("lfs_storage_by_networks_query_tuning", default: false)
        network_blob_total_sizes = network_ids.inject({}) { |hash, nw_id| hash[nw_id] = T.let(0, Numeric); hash }

        # We only have one index that will suffice here as a covering index, the
        # index_media_blobs_on_state_repo_network_id_created_at_and_size index,
        # which for historical reasons contains the created_at column,
        # although it is no longer required.
        # Since the id column is automatically appended as the last part of
        # any index, we can use this to sort our records in a fixed order
        # even if they have the same repository_network_id, created_at, and
        # size values, and so we are able to step through them in batches.
        sql = <<-SQL
          WITH blobs AS (
              SELECT repository_network_id, created_at, size, id
                FROM media_blobs
               WHERE repository_network_id IN (:network_ids)
                 AND state = :state
                 AND (repository_network_id > :last_repository_network_id OR
                      (repository_network_id = :last_repository_network_id AND
                       (created_at > :last_created_at OR
                        (created_at = :last_created_at AND
                         (size > :last_size OR
                          (size = :last_size AND id > :last_id))))))
               ORDER BY repository_network_id, created_at, size, id
               LIMIT :batch_size
            ),
            network_totals AS (
              SELECT repository_network_id,
                     SUM(size) AS blob_total_size
                FROM blobs
               GROUP BY repository_network_id
            ),
            last_blobs AS (
              SELECT repository_network_id AS last_repository_network_id,
                     created_at AS last_created_at,
                     size AS last_size,
                     id AS last_id
                FROM blobs
               ORDER BY repository_network_id DESC, created_at DESC,
                        size DESC, id DESC
               LIMIT 1
            )
          SELECT nt.repository_network_id,
                 nt.blob_total_size,
                 (SELECT COUNT(*) FROM blobs) AS blob_count,
                 lb.last_repository_network_id,
                 lb.last_created_at,
                 lb.last_size,
                 lb.last_id
            FROM network_totals nt
           CROSS JOIN last_blobs lb
           ORDER BY nt.repository_network_id
        SQL

        last_repository_network_id = T.let(0, T.untyped)
        last_created_at = Time.new(2000, 1, 1)
        last_size = T.let(0, T.untyped)
        last_id = T.let(0, T.untyped)

        ActiveRecord::Base.connected_to(role: :reading) do
          while true
            sql_bindings = {
              network_ids: network_ids,
              state: VERIFIED,
              last_repository_network_id: last_repository_network_id,
              last_created_at: last_created_at,
              last_size: last_size,
              last_id: last_id,
              batch_size: Arel.sql(blob_batch_size.to_s),
            }

            query = Arel.sql(sql, **sql_bindings)
            rows = ApplicationRecord::Domain::Assets.connection.select_rows(query)
            break if rows.nil? || rows.first.nil?

            rows.each do |row|
              # These should never be nil, but to be safe we check anyway.
              next if row[0].nil? || row[1].nil?

              # Note that ActiveRecord reports SUM() values as BigDecimal objects.
              network_blob_total_sizes[row[0]] += row[1]
            end

            last_row = rows.last
            break if last_row[2] < blob_batch_size

            last_repository_network_id = last_row[3]
            last_created_at = last_row[4]
            last_size = last_row[5]
            last_id = last_row[6]
          end
        end

        network_blob_total_sizes
      else
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
end
