# typed: false
# frozen_string_literal: true

module GitHub
  class DGit
    # A strategy class for assigning readweights for a set of replicas.
    #
    # Each datacenter should have a total of 100 points.
    #
    # By default, one replica will get all 100 points. Choose a voting
    # replica to get all 100 points when possible.
    #
    # If the points are spread out across multiple replicas already,
    # try to preserve the character of them. If a new replica is getting
    # added, give it a weight that's proportional to the rest of the
    # weights.
    class ReadWeightAllocator
      # Figure out what the read weights should be for the
      # given set of replicas.
      #
      # `replicas` can be an array of GitHub::DGit::Replica
      # or GitHub::DGit::Fileserver objects.
      #
      # Returns a hash of {hostname => weight}
      def choose_read_weights(replicas, new_host: nil)
        replicas_by_dc = replicas.group_by(&:datacenter)
        replicas_by_dc.each_with_object({}) do |(_dc, replicas), weights|
          weights.update choose_read_weights_for_dc_replicas(replicas, new_host: new_host)
        end
      end

      # Adapt Fileserver objects so they look like replicas.
      #
      # See NewlyAllocatedReplica at the end of this file.
      def new_replicas(fileservers)
        fileservers.map { |fs| NewlyAllocatedReplica.new(fs) }
      end

      private

      def choose_read_weights_for_dc_replicas(replicas, new_host: nil)
        active = replicas.select(&:active?)
        voting = active.select(&:voting?)
        active_weight = active.map(&:read_weight).inject(0, &:+)
        voting_weight = voting.map(&:read_weight).inject(0, &:+)

        weights =
          if voting_weight == 0 && voting.size > 0
            alloc(voting)
          elsif active_weight == 0
            alloc(active)
          else
            redistribute_balanced_read_weight(replicas, new_host: new_host)
          end

        # Any replica not touched above should be zero.
        replicas.each do |repl|
          weights[repl.host] ||= 0
        end

        weights
      end

      # Like GitHub::DGit.alloc_read_weight, but it takes an array of Replica objects.
      #
      # Returns a mapping of hostname to read weight for the provided hosts.
      def alloc(replicas)
        online = replicas.select(&:online?)
        online = replicas if online.empty?
        preferred = online.reject(&:hdd_storage?)
        preferred = online if preferred.empty?
        reader = preferred[rand(preferred.size)]
        Hash[replicas.map { |rep| [rep.host, rep == reader ? 100 : 0] }]
      end

      # Try to preserve the character of the existing read_weights.
      # Is one of them 100?  Leave it that way.  Are they balanced
      # somehow?  Allocate some of the points to the new host, if
      # there is one.  Normalize after.
      def redistribute_balanced_read_weight(replicas, new_host: nil)
        active = replicas.select(&:active?)
        total_weight = active.map(&:read_weight).inject(0, &:+)
        is_balanced = active.map(&:read_weight).count { |w| w > 0 } > 1

        weights = Hash[active.map { |r| [r.host, r.read_weight] }]
        if is_balanced && new_host && weights[new_host] == 0 && active.size > 1
          weights[new_host] = total_weight / (active.size - 1)
          total_weight += weights[new_host]
        end

        # Normalize to 100.
        if total_weight != 100
          weights.each do |k, v|
            weights[k] = v * 100 / total_weight
          end

          # fix any rounding errors
          newsum = weights.values.inject(&:+)
          if newsum != 100
            weights[weights.first.first] += 100 - newsum
          end
        end

        weights
      end

      # When choosing readweights for a new repository or gist,
      # there won't be replica records yet, only fileservers. This
      # class adapts the Fileserver object so that it can be used
      # by the readweight allocator.
      class NewlyAllocatedReplica
        def initialize(fileserver)
          @fileserver = fileserver
        end

        def datacenter
          @fileserver.datacenter
        end

        def online?
          @fileserver.online?
        end

        def voting?
          @fileserver.contains_voting_replicas?
        end

        def host
          @fileserver.name
        end

        # Initially, there is no readweight.
        def read_weight
          0
        end

        # It's not active yet, but we're aspiring to be.
        def active?
          true
        end

        def hdd_storage?
          @fileserver.hdd_storage?
        end
      end
    end
  end
end
