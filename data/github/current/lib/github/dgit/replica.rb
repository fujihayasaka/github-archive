# typed: false
# frozen_string_literal: true

module GitHub
  class DGit
    module Replica
      class Base
        # Online and quiescing are stored as fileserver attributes,
        # but they're mainly relevant when dealing with a replica.
        #
        # - quiescing is only considered when choosing which replica
        #   to read from.
        #
        # - online is used to filter fileservers during host selection,
        #   but its real relevance is when deciding what to do with a
        #   replica.
        #
        # If these become useful on the Fileserver instance, then please
        # move them.
        def initialize(db_name:, fileserver:, read_weight:, quiescing:, state:, created_at:, updated_at:)
          @db_name = db_name
          @fileserver = fileserver
          @quiescing = quiescing
          @read_weight = read_weight
          @state = state
          @created_at = created_at
          @updated_at = updated_at
        end

        # The database where this replica was looked up.
        attr_reader :db_name

        # The Fileserver where this replica is
        attr_reader :fileserver

        # One of the state constants defined in GitHub::DGit
        attr_reader :state

        # The read_weight that's recorded in the database.
        attr_reader :read_weight

        # The time this replica was created
        attr_reader :created_at

        # The time this replica was most recently updated
        attr_reader :updated_at

        def compare_time(a, b)
          a.year == b.year &&
            a.month == b.month &&
            a.day == b.day &&
            a.hour == b.hour &&
            a.min == b.min &&
            a.sec == b.sec
        end

        def ==(other_base)
          db_name == other_base.db_name &&
            fileserver == other_base.fileserver &&
            quiescing? == other_base.quiescing? &&
            state == other_base.state &&
            compare_time(created_at, other_base.created_at) &&
            compare_time(updated_at, other_base.updated_at)
        end

        def host;        fileserver.name;        end
        def datacenter;  fileserver.datacenter;  end
        def evacuating?; fileserver.evacuating?; end
        def online?;     fileserver.online?;     end
        def quiescing?;  @quiescing;             end
        def cache_location; fileserver.cache_location; end

        def region
          GitHub::DGit::Util.datacenter_region(datacenter)
        end

        def voting?
          @fileserver.contains_voting_replicas?
        end

        def hdd_storage?
          @fileserver.hdd_storage?
        end

        def active?; state == GitHub::DGit::ACTIVE; end
        def dormant?; state == GitHub::DGit::DORMANT; end
        def destroying?; state == GitHub::DGit::DESTROYING; end
        def repairing?; state == GitHub::DGit::REPAIRING; end

        def healthy?
          online? && active?
        end

        def in_datacenter?(dc:)
          datacenter == dc
        end

        def in_region?(dc:)
          return false if region.nil?
          GitHub::DGit::Util.datacenter_region(dc) == region
        end

        def cache_replica?
          @fileserver.cache_server?
        end

        def in_cache_location?(cl)
          cache_location == cl
        end

        def to_route(path)
          fileserver.to_route(path, read_weight: read_weight, quiescing: quiescing?, healthy: healthy?)
        end

        def to_db_row
          [state, host, read_weight, created_at, updated_at]
        end
      end

      module Checksummed
        def initialize(checksum:, expected_checksum:, **rest)
          super(**rest)
          @checksum = checksum
          @expected_checksum = expected_checksum
        end

        attr_reader :checksum, :expected_checksum

        def checksum_ok?
          checksum == expected_checksum || checksum == "ok"
        end

        def cache_checksum_ok?
          # Cache replica checksums usually have the "cache:" prefix
          # (followed by the checksum of the last data synced from the
          # primary; it's ok if this is behind expected_checksum).
          #
          # If a cache replica has a checksum in the normal non-cache replica
          # format (regardless of value), we tolerate that too.  This can
          # happen e.g. if all replica checksums got recomputed.
          #
          # We reject other checksums, e.g. "creating" or "bad", which
          # indicate that the data really isn't available.
          checksum.start_with?("cache:") || checksum == "ok" || checksum.match(/\A\d+:/)
        end

        def cache_in_sync?
          checksum == "cache:" + expected_checksum
        end

        def healthy?
          super && checksum_ok?
        end

        def healthy_cache?
          online? && active? && cache_checksum_ok?
        end

        def to_db_row
          super() << checksum
        end

        def ==(other)
          super(other) &&
            checksum == other.checksum &&
            expected_checksum == other.expected_checksum
        end
      end

      module Networked
        def initialize(db_network_replica_id:, **rest)
          super(**rest)
          @db_network_replica_id = db_network_replica_id
        end

        # The underlying database id for the network_replica row
        attr_reader :db_network_replica_id
        def ==(other)
          super(other) &&
            db_network_replica_id == other.db_network_replica_id
        end
      end

      class Repo < Base
        include Checksummed
        include Networked
      end

      class Network < Base
        include Networked
      end

      class Gist < Base
        include Checksummed
      end
    end
  end
end
