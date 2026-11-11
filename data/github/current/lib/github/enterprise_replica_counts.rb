# typed: true
# frozen_string_literal: true

require "application_record/pages"
require "application_record/domain/spokes"
require "application_record/domain/storage"
require "github/config/cache_store"

module GitHub
  # EnterpriseReplicaCounts provides methods to query MySQL directly for
  # voting and non-voting replica counts in GHES (GitHub Enterprise Server).
  #
  # These methods replace the environment variable-based configuration
  # for dgit, pages, and storage replica counts in enterprise environments.
  # The data is queried from the fileservers, pages_fileservers, and
  # storage_file_servers tables respectively.
  module EnterpriseReplicaCounts
    # Cache TTL for replica counts to avoid excessive database queries
    REPLICA_COUNT_CACHE_TTL = 60.seconds

    # Get the number of voting copies for git (dgit).
    # Queries the fileservers table for online, voting servers.
    # Returns 3 if more than 1 server exists, otherwise returns 1.
    #
    # @return [Integer] the number of voting git fileservers (minimum 1)
    def self.dgit_voting_copies
      GitHub.cache.fetch("enterprise_replica_counts.dgit_voting_copies", ttl: REPLICA_COUNT_CACHE_TTL) do
        count = ApplicationRecord::Domain::Spokes.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM fileservers
          WHERE online = 1
            AND non_voting = 0
            AND (cache_location IS NULL OR cache_location = '')
        SQL
        count > 1 ? 3 : 1
      end
    end

    # Get the number of non-voting copies for git (dgit).
    # Queries the fileservers table for online, non-voting servers.
    # Excludes cache servers.
    #
    # In cluster mode (voting_copies > 1), returns voting_copies if any
    # non-voting servers exist, otherwise returns 0.
    #
    # @return [Integer] the number of non-voting git fileservers (0 if none)
    def self.dgit_non_voting_copies
      GitHub.cache.fetch("enterprise_replica_counts.dgit_non_voting_copies", ttl: REPLICA_COUNT_CACHE_TTL) do
        non_voting_count = ApplicationRecord::Domain::Spokes.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM fileservers
          WHERE online = 1
            AND non_voting = 1
            AND (cache_location IS NULL OR cache_location = '')
        SQL

        voting_copies = dgit_voting_copies
        if voting_copies > 1 && non_voting_count > 0
          # Cluster HA mode: return voting_copies if any non-voting servers exist
          voting_copies
        else
          non_voting_count
        end
      end
    end

    # Get the number of voting replicas for pages.
    # Queries the pages_fileservers table for online, voting servers.
    # Returns 3 if more than 1 server exists, otherwise returns 1.
    #
    # @return [Integer] the number of voting pages fileservers (minimum 1)
    def self.pages_voting_replica_count
      GitHub.cache.fetch("enterprise_replica_counts.pages_voting_replica_count", ttl: REPLICA_COUNT_CACHE_TTL) do
        count = ApplicationRecord::Pages.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM pages_fileservers
          WHERE online = 1
            AND non_voting = 0
        SQL
        count > 1 ? 3 : 1
      end
    end

    # Get the number of non-voting replicas for pages.
    # Queries the pages_fileservers table for online, non-voting servers.
    #
    # In cluster mode (voting_replica_count > 1), returns voting_replica_count
    # if any non-voting servers exist, otherwise returns 0.
    #
    # @return [Integer] the number of non-voting pages fileservers (0 if none)
    def self.pages_non_voting_replica_count
      GitHub.cache.fetch("enterprise_replica_counts.pages_non_voting_replica_count", ttl: REPLICA_COUNT_CACHE_TTL) do
        non_voting_count = ApplicationRecord::Pages.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM pages_fileservers
          WHERE online = 1
            AND non_voting = 1
        SQL

        voting_replica_count = pages_voting_replica_count
        if voting_replica_count > 1 && non_voting_count > 0
          # Cluster HA mode: return voting_replica_count if any non-voting servers exist
          voting_replica_count
        else
          non_voting_count
        end
      end
    end

    # Get the number of voting replicas for storage.
    # Queries the storage_file_servers table for online, voting servers.
    # Excludes cache servers.
    # Returns 3 if more than 1 server exists, otherwise returns 1.
    #
    # @return [Integer] the number of voting storage fileservers (minimum 1)
    def self.storage_voting_replica_count
      GitHub.cache.fetch("enterprise_replica_counts.storage_voting_replica_count", ttl: REPLICA_COUNT_CACHE_TTL) do
        count = ApplicationRecord::Domain::Storage.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM storage_file_servers
          WHERE online = 1
            AND non_voting = 0
            AND (cache_location IS NULL OR cache_location = '')
        SQL
        count > 1 ? 3 : 1
      end
    end

    # Get the number of non-voting replicas for storage.
    # Queries the storage_file_servers table for online, non-voting servers.
    # Excludes cache servers.
    #
    # In cluster mode (voting_replica_count > 1), returns voting_replica_count
    # if any non-voting servers exist, otherwise returns 0.
    #
    # @return [Integer] the number of non-voting storage fileservers (0 if none)
    def self.storage_non_voting_replica_count
      GitHub.cache.fetch("enterprise_replica_counts.storage_non_voting_replica_count", ttl: REPLICA_COUNT_CACHE_TTL) do
        non_voting_count = ApplicationRecord::Domain::Storage.connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM storage_file_servers
          WHERE online = 1
            AND non_voting = 1
            AND (cache_location IS NULL OR cache_location = '')
        SQL

        voting_replica_count = storage_voting_replica_count
        if voting_replica_count > 1 && non_voting_count > 0
          # Cluster HA mode: return voting_replica_count if any non-voting servers exist
          voting_replica_count
        else
          non_voting_count
        end
      end
    end
  end
end
