# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class ReachabilityClient < DependencyGraphPlatform::Twirp::BaseClient
      READ_TIMEOUT = 10 # seconds
      DEFAULT_WAIT_INTERVAL = 1 # seconds
      DEFAULT_MAX_ATTEMPTS = 10

      class DependenciesJobFailed < BaseError; end
      class AttemptsExhausted < BaseError; end

      sig { params(repository_id: Integer, commit_oid: String, include_malformed_dependencies: T::Boolean).returns(Github::DependencyGraphPlatform::Reachability::V1::GetDependenciesResponse) }
      def get_dependencies(repository_id:, commit_oid:, include_malformed_dependencies: false)
        req = {
          repository_id: repository_id,
          commit_oid: commit_oid,
        }
        req[:include_malformed_dependencies] = true if include_malformed_dependencies

        res = rpc(:GetDependencies, req)
        increment_job_status(res.status, :get_dependencies)

        res
      end

      def wait_for_dependencies(repository_id:, commit_oid:, include_malformed_dependencies: false, wait_interval: DEFAULT_WAIT_INTERVAL, max_attempts: DEFAULT_MAX_ATTEMPTS)
        start_time = Time.now
        attempts = 0

        loop do
          attempts += 1
          response = get_dependencies(repository_id:, commit_oid:, include_malformed_dependencies:)
          status = response.status

          unless status == :JOB_STATUS_PROCESSING
            wait_for_deps_stats(response:, attempts:, start_time:)

            case status
            when :JOB_STATUS_COMPLETED
              return response
            when :JOB_STATUS_FAILED
              report_and_raise(DependenciesJobFailed.new("GetDependencies job failed to obtain dependencies."))
            end
          end

          if attempts >= max_attempts
            wait_for_deps_stats(response:, attempts:, start_time:)
            report_and_raise(AttemptsExhausted.new("Maximum attempts to obtain dependencies has been reached."))
          end

          sleep(wait_interval)
        end

      end

      private

      def wait_for_deps_stats(response:, attempts:, start_time:)
        status = status_tag(response.status)
        track_response_time_for(:wait_for_dependencies, start_time, tags: ["final_status:#{status}"])
        increment_job_status(status, :wait_for_dependencies)
        count_request_attempts(:wait_for_dependencies, attempts, tags: ["final_status:#{status}"])
      end

      def increment_job_status(status, method)
        GitHub.dogstats.increment("#{DATADOG_PREFIX}.#{client_name}.#{method_tag(method)}.status", tags: ["status:#{status_tag(status)}"])
      end

      def status_tag(status)
        status.to_s.downcase.split("_").last
      end

      def client_name
        "reachability"
      end

      def twirp_class
        Github::DependencyGraphPlatform::Reachability::V1::DependenciesAPIClient
      end
    end
  end
end
