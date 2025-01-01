# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class AlertingClient < DependencyGraphPlatform::Twirp::BaseClient
      class AlertingError < BaseError; end

      ECOSYSTEM_HASH = {
        "npm" => :ECOSYSTEM_NPM,
        "maven" => :ECOSYSTEM_MAVEN,
      }

      # This error is raised when the AsyncAccessMiddleware determines the response is only a stub response without
      # data. We will block and poll for the data by retrying within the client before giving up and bubbling
      # this error up to the calling job.
      #
      # The calling job will retry this error by requeuing with an expectation of eventual success for very large
      # repositories as long as the SHA being fetched remains stable between retries.
      #
      # We should only expect this error to hit Failbot in the situation where a repository is never able to achieve
      # success after exhausting job retries.
      class AlertingFetchNotReady < DependencyGraphPlatform::Twirp::Error; end

      # This error is raised when the AsyncAccessMiddleware determines the response is corresponding to a repository
      # that is blocked from being analyzed.
      #
      # This is a non-retryable error and is used as a fast-fail to avoid mutating alerts.
      class AlertingRepositoryBlocked < DependencyGraphPlatform::Twirp::NonRetryableError; end

      FETCH_RETRY_CONFIG = {
        # All twirp requests are POSTs
        methods: [:post],
        exceptions: [AlertingFetchNotReady],
        interval: 0.3, # seconds
        backoff_factor: 3,
        max: 6, # 0.3, 1.2, 3.9, 12.0, 36.3, 109.2
        retry_block: proc { GitHub.dogstats.increment("#{DATADOG_PREFIX}.async_access.retries") }
      }

      # Faraday middleware which obfuscates the asynchronous access pattern provided by DGP by intercepting any
      # responses that do not include data and raising an error
      class AsyncAccessMiddleware < ::Faraday::Middleware
        RPC_METHOD_TO_INTERCEPT = "FetchVulnerableDependenciesForRepository".freeze

        def call(env)
          @app.call(env).on_complete do |response_env|
            rpc_method = rpc_method_from(env)

            if rpc_method == RPC_METHOD_TO_INTERCEPT
              rpc_response_class = rpc_response_class(rpc_method)
              resp = ::Twirp::Encoding.decode(
                response_env.body,
                rpc_response_class,
                response_env.response_headers["Content-Type"]
              )

              if resp.status == :JOB_STATUS_PROCESSING
                raise AlertingFetchNotReady, "Still processing Repo ID '#{resp.repository_id}' at '#{resp.commit_oid}'"
              elsif resp.status == :JOB_STATUS_BLOCKED
                raise AlertingRepositoryBlocked, "Repository ID '#{resp.repository_id}' is blocked"
              end
            end
          end
        end

        def rpc_method_from(env)
          env.url.path.split("/").last
        end

        def rpc_response_class(rpc_method)
          client_class.rpcs.fetch(rpc_method).fetch(:output_class)
        end

        def client_class
          Github::DependencyGraphPlatform::Alerting::V1::AlertingAPIClient
        end
      end

      # Create a client configured for reporting requests that are likely have some outlier slow queries.
      #
      # :WARN: This should only be used from background jobs which can tolerate seconds-long requests.
      sig { returns(T.attached_class) }
      def self.new_reporting_client
        connection = self.build_connection(read_timeout_secs: 10)

        new(connection: connection)
      end

      # Create a client configured for on-demand repository content analysis requests.
      #
      # :WARN: This should only used from background jobs which can tolerate minutes-long requests
      sig { params(retry_options: Hash).returns(T.attached_class) }
      def self.new_fetch_client(retry_options: FETCH_RETRY_CONFIG)
        connection = self.build_connection(read_timeout_secs: 120)

        # The call order here is load-bearing - retries need to be higher in the response stack
        # then our async handler so they must be called in reverse order.
        connection.request :retry, retry_options # Configure our retry strategy
        connection.use AsyncAccessMiddleware     # Intercept any responses still in a processing state

        new(connection: connection)
      end

      sig { params(ecosystem: String, package_name: String, requirements: String, limit: Integer, cursor: T.nilable(T::Hash[Symbol, Integer])).returns(Github::DependencyGraphPlatform::Alerting::V1::AllRepositoriesWithDependencyVersionResponse) }
      def all_repositories_with_dependency_version(ecosystem:, package_name:, requirements:, limit:, cursor: nil)
        twirp_ecosystem = ECOSYSTEM_HASH.fetch(ecosystem, nil)
        if twirp_ecosystem.nil?
          raise ArgumentError.new("ecosystem must be one of #{ECOSYSTEM_HASH.keys}")
        end
        req = {
          package_ecosystem: twirp_ecosystem,
          package_name: package_name,
          requirements: requirements,
          pagination: {
            limit: limit,
          }
        }

        if cursor.present?
          req[:pagination][:cursor] = cursor
        end

        rpc(:AllRepositoriesWithDependencyVersion, req)
      end

      sig { params(repository_id: Integer, package_name: String, manifest_path: String, requirements: String, include_snapshots: T::Boolean).returns(Github::DependencyGraphPlatform::Alerting::V1::GetDependencyRelationshipsResponse) }
      def get_dependency_relationships(repository_id:, package_name:, manifest_path:, requirements:, include_snapshots:)
        req = {
          repository_id: repository_id,
          package_name: package_name,
          manifest_path: manifest_path,
          requirements: requirements,
          include_snapshots: include_snapshots
        }

        rpc(:GetDependencyRelationships, req)
      end

      sig { params(repository_id: Integer, commit_oid: String).returns(Github::DependencyGraphPlatform::Alerting::V1::FetchVulnerableDependenciesForRepositoryResponse) }
      def fetch_vulnerable_dependencies_for_repository(repository_id:, commit_oid:)
        req = {
          repository_id: repository_id,
          commit_oid: commit_oid
        }

        rpc(:FetchVulnerableDependenciesForRepository, req)
      end

      private

      def client_name
        "alerting"
      end

      def twirp_class
        Github::DependencyGraphPlatform::Alerting::V1::AlertingAPIClient
      end
    end
  end
end
