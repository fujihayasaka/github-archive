# typed: false
# frozen_string_literal: true

module GitHub
  class DGit
    class HostPicker
      # Choose 'count' hosts from 'fileserver_pool'.
      #
      # count (Integer)
      #   - number of hosts to return
      # fileserver_pool (Array of GitHub::DGit::Fileserver)
      #   - hosts to choose from
      #     defaults to all voting fileservers
      # exclusions (Array of String)
      #   - names of hosts that are not allowed to be picked
      #     This should be any hosts that already have replicas and
      #     any hosts that are too busy to receive replicas
      # far_from (Array of String)
      #   - names of hosts that have replicas already
      #     HostPicker will try to avoid picking hosts that are in
      #     the same placement zone (rack).
      # no_raise (Boolean)
      #   - should this raise an error if there aren't 'count' hosts available?
      def pick_fileservers(count, exclusions:, far_from:, fileserver_pool: nil, no_raise: false)
        fileservers = fileserver_pool || GitHub::DGit.get_fileservers(voting_only: true, exclude_embargoed: true)
        candidates = fileservers.reject { |fs| exclusions.include?(fs.name) }
        candidates = candidates.reject { |fs| fs.cache_server? }

        if candidates.size > count
          pick_by_weight(count, candidates, fileservers: fileservers, far_from: far_from, no_raise: no_raise)
        else
          pick_all(count, candidates, fileservers: fileservers, exclusions: exclusions, no_raise: no_raise)
        end
      end

      private

      # Choose all of the candidates.
      def pick_all(count, candidates, fileservers:, exclusions:, no_raise:)
        if candidates.size < count
          raise_or_report_error no_raise, "Not enough hosts: count=#{count}, candidates=#{candidates.size}",
            fileservers: fileservers,
            exclusions: exclusions
        end

        candidates
      end

      # Choose the candidates with the most free disk space.
      def pick_by_weight(count, candidates, fileservers:, far_from:, no_raise:)
        prepare_host_weights(candidates)
        far_from_zones = far_from.map { |fs| fs.placement_zone }.uniq.compact
        fallbacks, candidates = candidates.partition { |fs| far_from_zones.include?(fs.placement_zone) }

        # Candidates now contains all the hosts that are appropriately far
        # from everything in far_from.
        #
        # Fallbacks contains everything that's too close to something in
        # far_from.  They'll only get used if candidates becomes empty.
        #
        # We'll maintain those invariants as we pick hosts.  In particular,
        # each host we pick will shift other hosts near it from the
        # candidates list to the fallbacks list.

        ret = []
        count.times do
          if !candidates.empty?
            fileserver = weighted_selection(candidates)
            ret << fileserver
            # Move anything near `fileserver` into `fallbacks`.
            zone = fileserver.placement_zone
            new_fallbacks, candidates = candidates.partition { |fs| zone == fs.placement_zone }
            fallbacks += new_fallbacks
          end

          if candidates.empty?
            if fallbacks.size < count - ret.size
              fileserver_info =
                sprintf("%10s | %14s | %s\n", "Weight", "Disk Stats", "DC / Rack / Fileserver") +
                fileservers.map { |fs| sprintf("%10.5f | %5.1f%%/%5dG | %s / %s / %s\n", fs.weight, 100.0 * fs.disk_stats[0], fs.disk_stats[1], fs.datacenter, fs.rack, fs.name) }.join
              raise_or_report_error no_raise, "Not enough hosts: count=#{count}, ret=#{ret.inspect}, fallbacks=#{fallbacks.inspect}",
                exclusions: exclusions,
                far_from: far_from,
                far_from_zones: far_from_zones,
                fileserver_pool: fileserver_info
              break
            else
              (count - ret.size).times do
                ret << weighted_selection(fallbacks)
              end
              break
            end
          end
        end
        ret
      end

      def raise_or_report_error(no_raise, message, context)
        error = HostSelectionError.new(message)
        error.failbot_context.update(context)
        if no_raise
          error.set_backtrace(caller)
          Failbot.report! error, app: "github-dgit-debug"
        else
          raise error
        end
      end

      def prepare_host_weights(fileservers)
        GitHub::DGit::Fileserver.prefill_disk_stats(fileservers)

        # Prevent picking hosts with 10% less available disk space than the
        # emptiest host.  This keeps the disk-space-rebalancing algorithm
        # from thrashing -- see dgit/maintenance.rb.  Using a non-zero
        # weight means we'll still prefer a closer-to-full host over the
        # fallback (same rack) hosts.
        if !fileservers.empty?
          min_weight = fileservers.map(&:weight).min
          cutoff = [0, min_weight + MAX_DISK_SPACE_SPREAD].max
          cutoff = [cutoff, min_weight * 2].min
          fileservers.each do |host|
            if host.weight < cutoff
              host.weight = 0.00001
            end
          end
        end
      end

      # Pick an element out of a weighted list, remove it from the list, and
      # return the element.
      #
      #   - array: a list of candidates
      #      - example: [ "host1", "host2" ]
      #   - weights: a hash assigning weights to the values in the array
      #      - example: { "host1"=>2, "host2"=>5 }
      #
      # Return value: a random selection from the array.  If all the weights
      # are the same (including all zero), the selection is uniformly
      # random.  Otherwise, the selection is weighted by the weights.  If
      # only some of the weights are zero, those elements will not be
      # selected.
      #
      # IMPORTANT: the returned element is removed from the array.
      def weighted_selection(array)
        total_weight = array.map { |elem| elem.weight }.inject(&:+)
        if total_weight == 0
          idx = rand(array.size)
        else
          r = rand * total_weight
          idx = array.index { |x| (r -= x.weight) < 0 }
        end
        array.slice!(idx)
      end
    end
  end
end
