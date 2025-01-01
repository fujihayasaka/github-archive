# typed: true
# frozen_string_literal: true

# Transition to backfill RepositoryNetwork records for existing repository
# networks.
#
# By default this script creates network records for all missing networks.
# If an owner name is passed as the first argument, the operation will be
# limited to repositories belonging to that owner only.
#
# Run this manually in production with something like:
#
#   $ ssh -t ops-aux2-cp1-prd.iad.github.net
#   $ gh-screen
#   $ gudo divvy -v -n 2 backfill_repository_networks.rb | tee backfill.log
#
require "time"
require "divvy"
require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillRepositoryNetworks
      include Divvy::Parallelizable

      def initialize(owner = nil)
        if owner
          @owner = User.find_by_login(owner)
          fail "owner not found: #{owner.inspect}" if @owner.nil?
        end

        @total = count_missing_networks
        @count = 0
      end

      def dispatch
        loop do
          network_ids = find_missing_networks
          break if network_ids.empty?

          network_ids.each do |network_id|
            @count += 1
            status "network: %d (%d/%d, %02d%%)", network_id, @count, @total, (@count / @total.to_f) * 100
            yield network_id
          end
        end
      end

      def process(network_id)
        log "creating network #{network_id}"
        RepositoryNetwork.backfill!(network_id)
      end

      def perform
        dispatch { |network_id| process(network_id) }
      end

      # Find networks that don't have a RepositoryNetwork record yet. This is
      # surprisingly fast (~0.6s), I assume due to the limit. It runs on the
      # primary DB because we need a consistent view of what networks have been
      # backfilled.
      #
      # Returns an array of integer network ids.
      def find_missing_networks
        select_values("
          SELECT DISTINCT source_id
            FROM repositories
           WHERE NOT EXISTS (SELECT * FROM repository_networks n WHERE n.id = source_id)
             AND active = 1
             #{owner_conditions}
           ORDER BY source_id ASC
           LIMIT 500
        ")
      end

      # Count networks that don't have RepositoryNetwork records yet. This is
      # super slow and expensive (30s) and is run on the secondary to prevent
      # loading the primary too much.
      #
      # Returns the number of networks that haven't been backfilled yet.
      def count_missing_networks
        ActiveRecord::Base.connected_to(role: :reading) do
          select_values("
           SELECT COUNT(DISTINCT source_id)
             FROM repositories
            WHERE NOT EXISTS (SELECT * FROM repository_networks n WHERE n.id = source_id)
              AND active = 1
              #{owner_conditions}
          ").first
        end
      end

      def owner_conditions
        "AND owner_id = #{@owner.id}" if @owner
      end

      # Execute a SQL query.
      def select_values(query)
        RepositoryNetwork.connection.select_values(query)
      end

      # Write log message to stdout.
      def log(message)
        return if Rails.env.test?
        puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
      end

      # Write live-updating status message to stderr.
      def status(message, *args)
        return if Rails.env.test? || !$stderr.tty? || $stdout.tty?
        $stderr.printf(" #{message}\r", *args)
      end

      # Tap into the after_fork hook to re-establish DB connection.
      # Redis and Memcached would go here but their connections are established
      # on demand, so the master never opens a socket.
      def after_fork(worker)
        RepositoryNetwork.establish_connection
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  trans = GitHub::Transitions::BackfillRepositoryNetworks.new(ARGV[0])
  trans.perform
end
