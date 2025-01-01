# typed: true
# frozen_string_literal: true

##
# GitHub amen / statsd connection.

require "github"
require "datadog/statsd"
require "github/statsd"
require "github/dogstats"
require "resolv"

module GitHub
  module Config
    module Stats
      include Kernel

      attr_writer :stats

      def stats
        return @stats if defined?(@stats)
        @stats = create_statsd(namespace: "github")
      end

      def create_statsd(namespace:)
        statsd = if GitHub.graphite_disabled?
          GitHub::NullStatsD.new
        elsif GitHub.stats_allowlist
          require "github/statsd/allowlist"
          GitHub::Statsd::Allowlist.new(GitHub.stats_allowlist)
        else
          GitHub::Statsd.new
        end

        GitHub.stats_hosts.each { |shard| statsd.add_shard(shard) }
        statsd.namespace = namespace
        statsd
      end

      # Private: Default host for dogstatsd.
      DEFAULT_DOGSTATSD_HOST = "127.0.0.1".freeze

      # Private: Default port for dogstatsd.
      DEFAULT_DOGSTATSD_PORT = 28125

      def default_tags
        tags = [
          "application:github",
          "application_role:#{GitHub.role}",
          "application_component:#{GitHub.component}",
          "deployed_to:#{GitHub.deployed_to}",
        ]

        if GitHub.kube?
          tags += kubernetes_tags
        end

        tags
      end

      def kubernetes_tags
        kube_tags = [
          "kube_namespace:#{GitHub.kubernetes_namespace}",
        ]

        kube_tags
      end

      def user_specified_tags
        ENV["DOGSTATSD_ADDITIONAL_TAGS"].to_s.split(",")
      end

      def dogtags
        default_tags + user_specified_tags
      end

      # Public: Statsd instance pointed at DataDog.
      def dogstats
        @dogstats ||= new_dogstats
      end

      def new_dogstats
        if GitHub.datadog_enabled?
          # The statsd client doesn't cache the hostname, so we do it here
          # to reduce the volume of DNS queries, which caused noticable
          # performance degradation in the Kubernetes environment.
          host = Resolv.getaddress(GitHub.environment.fetch("DOGSTATSD_HOST", DEFAULT_DOGSTATSD_HOST))
          port = (ENV["DOGSTATSD_PORT"] || DEFAULT_DOGSTATSD_PORT).to_i

          GitHub::Dogstats.new(host, port, tags: dogtags)
        elsif ENV["DOGSTATSD_DEBUG"]
          GitHub::DebugDogstatsD.new
        else
          GitHub::NullDogstatsD.new
        end
      end

      def close_dogstats
        @dogstats.close unless @dogstats.nil?
        @dogstats = nil
      end

      # When GitHub.component or GitHub.role change, we need to reset the tags
      # so that they are accurate (see #dogstats)
      def reset_dogtags
        if @dogstats
          dogstats.tags = dogtags
        end
      end
    end
  end

  extend Config::Stats

  # global variable used by external libraries (slumlord, raindrops):
  $stats = stats if !defined?($stats)

  # close dogstats on process termination to flush any unsent data
  at_exit do
    GitHub.close_dogstats
  end
end
