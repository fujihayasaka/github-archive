# typed: true
# frozen_string_literal: true

require "github/dgit/states"

module GitHub
  class DGit
    module ReplicationStrategy
      OK_VOTING_STATES = [ACTIVE, CREATING, REPAIRING].freeze
      OK_NON_VOTING_STATES = (OK_VOTING_STATES + [DORMANT]).freeze

      # When a network is in cold storage, we aim to keep one copy on
      # an ssd-based fileserver, and two on cheaper hdd-based fileservers.
      COLD_TARGET_SSD_COPIES = 1
      COLD_TARGET_HDD_COPIES = 2

      # Creates a ReplicationStrategy that can be used to check an array of replicas
      # for consistency against the replication rules.
      #
      # * fileservers - an array of Fileserver objects for all online servers
      # * bad_hosts - an array of hostnames of servers considered bad
      # * voting_strategy - a strategy to replace the default voting-server strategy
      #
      # Returns the new strategy object
      def self.new(fileservers, bad_hosts: [], voting_strategy: nil, config: GitHub, entity_type: GitHub::DGit::RepoType::NETWORK)
        voting, non_voting = fileservers.partition(&:contains_voting_replicas?)
        cache_hosts, non_voting = non_voting.partition(&:cache_server?)
        voting = voting.index_by(&:name)
        non_voting = non_voting.index_by(&:name)
        bad_hosts = bad_hosts.each_with_object({}) { |fs, h| h[fs] = true }

        # Since we use `dgit_default_copies` here, read-heavy networks are not properly supported!
        voting_strategy ||= ReplicaCounter.new(fileservers: voting, copies: config.dgit_default_copies, states: OK_VOTING_STATES, voting: true)

        multi_strategies = [voting_strategy]
        if !config.dgit_non_voting_copies.nil?
          multi_strategies << ReplicaCounter.new(fileservers: non_voting, copies: config.dgit_non_voting_copies, states: OK_NON_VOTING_STATES, voting: false)
        end

        cache_hosts_by_location = Hash.new { |h, k| h[k] = {} }
        cache_hosts.each { |fs| cache_hosts_by_location[fs.cache_location][fs.name] = fs }
        cache_hosts_by_location.each do |loc, servers|
          multi_strategies << CacheReplicaCounter.new(fileservers: servers, states: OK_VOTING_STATES, entity_type: entity_type, cache: loc)
        end

        Priority.new \
          Multi.new(*multi_strategies),
          ReplicaCounter.new(fileservers: bad_hosts, copies: 0, states: nil, stale: true)
      end

      # Combine the results from a couple of strategies.
      class Multi
        def initialize(*strategies)
          @strategies = strategies
        end

        def violations(id, replicas)
          @strategies.inject([]) { |res, strategy| res.concat(strategy.violations(id, replicas)) }
        end
      end

      # Returns the results from the first strategy that detects a problem
      class Priority
        def initialize(*strategies)
          @strategies = strategies
        end

        def violations(id, replicas)
          @strategies.inject([]) { |res, strategy| res.empty? ? res.concat(strategy.violations(id, replicas)) : res }
        end
      end

      # Select strategy as late as possible, using supplied block
      class LazyStrategy
        def initialize(&block)
          @supply_strategy = block
        end

        def violations(id, replicas)
          strategy = @supply_strategy.call(id, replicas)
          strategy.violations(id, replicas)
        end
      end

      # Count replicas that come from the given set of fileservers
      # with the given states (or any if nil supplied).
      class ReplicaCounter
        def initialize(fileservers:, states:, copies:, **info)
          @fileservers = fileservers
          @states = states.nil? ? nil : states.index_by { |state| state }
          @copies = copies
          @info = info.freeze
        end

        def inspect
          "#<ReplicaCounter: @copies=#{@copies}, @info=#{@info.inspect}, @fileservers=[...#{@fileservers.size}...], @states=[#{@states.nil? ? "*" : @states.keys.map { |state| STATES[state] || state }.join(",")}]"
        end

        def violations(id, replicas)
          copies = replicas.count { |_, host, state| @fileservers.key?(host) && (@states.nil? || @states.key?(state)) }
          if @copies != copies
            [[id, copies, @copies, @info]]
          else
            []
          end
        end
      end

      class CacheReplicaCounter
        def initialize(fileservers:, states:, entity_type:, **info)
          @fileservers = fileservers
          @states = states.nil? ? nil : states.index_by { |state| state }
          @entity_type = entity_type
          @info = info.freeze
        end

        def inspect
          "#<CacheReplicaCounter: @info=#{@info.inspect}, @entity_type=#{@entity_type}, @fileservers=[...#{@fileservers.size}...], @states=[#{@states.nil? ? "*" : @states.keys.map { |state| STATES[state] || state }.join(",")}]"
        end

        def violations(id, replicas)
          copies = replicas.count { |_, host, state| @fileservers.key?(host) && (@states.nil? || @states.key?(state)) }
          policy_counts = ActiveRecord::Base.connected_to(role: :reading) do
            sql = GitHub::DGit::DB.for_network_id(id).SQL.new(<<-SQL, network_id: id, cache_location: @info[:cache], entity_type: @entity_type)
              SELECT number_of_replicas FROM cache_storage_policies WHERE entity_type = :entity_type AND entity_id IN (0, :network_id) AND cache_location = :cache_location ORDER BY entity_id
            SQL
            [0] + sql.values
          end
          wanted_copies = policy_counts.last
          if wanted_copies != copies
            [[id, copies, wanted_copies, @info]]
          else
            []
          end
        end
      end

      # Count replicas that come from the given set of fileservers
      # with the given states (or any if nil supplied).
      class ReplicaCountRange
        def initialize(fileservers:, states:, min_copies:, max_copies:, **info)
          @fileservers = fileservers
          @states = states.nil? ? nil : states.index_by { |state| state }
          @min_copies = min_copies
          @max_copies = max_copies
          @info = info.freeze
        end

        def inspect
          "#<ReplicaCountRange: @min_copies=#{@min_copies}, @max_copies=#{@max_copies}, @info=#{@info.inspect}, @fileservers=[...#{@fileservers.size}...], @states=[#{@states.nil? ? "*" : @states.keys.map { |state| STATES[state] || state }.join(",")}]"
        end

        def violations(id, replicas)
          copies = replicas.count { |_, host, state| @fileservers.key?(host) && (@states.nil? || @states.key?(state)) }
          case
          when copies < @min_copies
            [[id, copies, @min_copies, @info]]
          when copies > @max_copies
            [[id, copies, @max_copies, @info]]
          else
            []
          end
        end
      end

      class ColdStorageCounter
        def initialize(fileservers:, datacenters:)
          @fileservers = fileservers.index_by(&:name)
          @states = OK_VOTING_STATES.index_by { |state| state }
          @datacenters = datacenters
        end

        def inspect
          "#<ColdStorageCounter: @fileservers=[...#{@fileservers.size}...], @states=[#{@states.keys.map { |state| STATES[state] || state }.join(",")}]"
        end

        def violations(id, replicas)
          rs_fs = replicas.map { |_, host, state| [state, @fileservers.fetch(host, nil)] }
          valid_rs = rs_fs.keep_if { |state, fs| fs && @states.key?(state) }
          v = []

          @datacenters.each do |dc|
            r = valid_rs.select { |_state, fs| fs.datacenter == dc }

            ssd_copies = r.count { |_state, fs| !fs.hdd_storage? }
            hdd_copies = r.count { |_state, fs| fs.hdd_storage? }

            # Prioritise adding new copies over deleting extra ones
            if too_few?(ssd: ssd_copies, hdd: hdd_copies)
              v << [id, ssd_copies, COLD_TARGET_SSD_COPIES, { cold_storage: false, datacenter: dc }] if too_few?(ssd: ssd_copies)
              v << [id, hdd_copies, COLD_TARGET_HDD_COPIES, { cold_storage: true, datacenter: dc }] if too_few?(hdd: hdd_copies)
            else
              v << [id, ssd_copies, COLD_TARGET_SSD_COPIES, { cold_storage: false, datacenter: dc }] if too_many?(ssd: ssd_copies)
              v << [id, hdd_copies, COLD_TARGET_HDD_COPIES, { cold_storage: true, datacenter: dc }] if too_many?(hdd: hdd_copies)
            end
          end
          v
        end

        private

        def too_few?(ssd: COLD_TARGET_SSD_COPIES, hdd: COLD_TARGET_HDD_COPIES)
          ssd < COLD_TARGET_SSD_COPIES || hdd < COLD_TARGET_HDD_COPIES
        end

        def too_many?(ssd: COLD_TARGET_SSD_COPIES, hdd: COLD_TARGET_HDD_COPIES)
          ssd > COLD_TARGET_SSD_COPIES || hdd > COLD_TARGET_HDD_COPIES
        end
      end
    end
  end
end
