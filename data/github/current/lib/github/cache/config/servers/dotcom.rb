# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    class Config
      module Servers
        class Dotcom
          include GitHub::Memoizer

          PARTITION_CLUSTER_MAPPING = {
            global: "github",
            usercontent: "github-usercontent",
            htmlpipeline: "github-htmlpipeline",
            featureflag: "github-feature-flag",
            ryow: "github-ryow",
          }.freeze

          sig { params(partition: Symbol, sites: T.nilable(T::Array[String]), bypass_proxy: T::Boolean).returns(T.nilable(T::Array[String])) }
          def servers(partition:, sites:, bypass_proxy: false)
            # review lab uses its own local memcached cluster
            return ["cache:11211"] if GitHub.review_lab?

            # Allow per-partition server override via env var (e.g. for proxy routing in k8s).
            # Bypassed for regional cache clients that must connect directly to site backends.
            unless bypass_proxy
              env_key = "MEMCACHED_#{partition.to_s.upcase}_SERVERS"
              proxy_enabled = GitHub.kube? && ENV["MEMCACHED_PROXY_ENABLED"] == "true"
              if proxy_enabled && (override = ENV[env_key].presence)
                servers = override.split(",").filter_map { |s| s.strip.presence }
                return servers unless servers.empty?
              end
            end

            raise ArgumentError.new("Dotcom requires specifying sites") if sites.nil? || sites.empty?

            cluster = PARTITION_CLUSTER_MAPPING[partition]
            raise ArgumentError.new("No cluster found for partition: #{partition}") unless cluster

            cluster_config = server_config[cluster]
            return unless cluster_config
            cluster_config.filter_map { |site, servers| servers if sites.include?(site) }.flatten
          end

          private

          sig { returns(T::Hash[String, T::Hash[String, T::Array[String]]]) }
          memoize def server_config
            YAML.load(File.read(SERVER_CONFIG_PATH))[GitHub::AppEnvironment.env]
          end
        end
      end
    end
  end
end
