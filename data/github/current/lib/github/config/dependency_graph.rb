# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all settings related
    # to Dependency Graph services
    module DependencyGraph
      # TODO: Remove direct reads from ENV?
      #
      # Several values pull values from ENV directly if they are not assigned a value from an environment file which
      # is a legacy configuration behaviour.
      #
      # This 'side-loading' behaviour creates uncertainty about how our configuration points are injected and deviates
      # from the intent that `github/config/environments/default.rb` is the point of truth, used directly in proxima,
      # and overlayed for production and development with their respective environment files.
      #
      # See: GitHub::Config#load_environment_config (lib/github/config.rb:6542)

      # General DG service enablement for the monolith, used to gate access to most of our services.
      def dependency_graph_enabled?
        return @dependency_graph_enabled if defined?(@dependency_graph_enabled)
        !GitHub.enterprise?
      end
      attr_writer :dependency_graph_enabled

      ## DG-API
      def dependency_graph_api_url
        ENV["DEPENDENCY_GRAPH_API_URL"] || @dependency_graph_api_url
      end
      attr_writer :dependency_graph_api_url

      def dependency_graph_api_slow_query_url
        # just setting the DEPENDENCY_GRAPH_API_URL environment variable will set both the default and the slow query URL
        ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"] || @dependency_graph_api_slow_query_url || dependency_graph_api_url
      end
      attr_writer :dependency_graph_api_slow_query_url

      attr_accessor :dependency_graph_api_hmac_key

      ### Aqueduct config for sending jobs to the dependency graph service
      # See: lib/dependency_graph/cross_service_job.rb
      attr_accessor :aqueduct_dependency_graph_url
      attr_accessor :aqueduct_dependency_graph_send_secret
      attr_accessor :aqueduct_dependency_graph_api_key
      attr_accessor :aqueduct_dependency_graph_api_key_version

      ## DGP
      attr_accessor :dependency_graph_platform_url
      attr_accessor :dependency_graph_platform_hmac_keys

      ## DS-API
      def dependency_snapshots_api_url
        ENV["DEPENDENCY_SNAPSHOTS_API_URL"] || @dependency_snapshots_api_url
      end
      attr_writer :dependency_snapshots_api_url

      def dependency_snapshots_api_hmac_key
        # This is using the same key/env var as the dependency graph API for now
        @dependency_snapshots_api_hmac_key ||= ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"].to_s
      end
      attr_writer :dependency_snapshots_api_hmac_key

      # OSS License Compliance (OLC)
      attr_accessor :oss_license_compliance_url
      attr_accessor :oss_license_compliance_hmac_key

      ## Other features

      # Determine if Autosubmission is available in this environment.
      def dependency_graph_autosubmit_action_enabled?
        # Enabled by default in dotcom, disabled for enterprise, except if explicitly enabled via ghe config apply.
        return @dependency_graph_autosubmit_action_enabled if defined?(@dependency_graph_autosubmit_action_enabled)
        !GitHub.enterprise?
      end
      attr_writer :dependency_graph_autosubmit_action_enabled
    end
  end

  extend Config::DependencyGraph
end
