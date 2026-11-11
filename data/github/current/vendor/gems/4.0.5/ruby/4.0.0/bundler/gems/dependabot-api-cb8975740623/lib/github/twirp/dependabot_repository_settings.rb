# frozen_string_literal: true

require "twirp"

module GitHub
  module Twirp
    class DependabotRepositorySettings
      class Error < StandardError; end
      class NotFound < StandardError; end

      def initialize(client:)
        @client = client
      end

      # TODO: Consider moving metrics to a GitHub::Twirp::Client middleware the next time we add a client
      def get_repository_settings(repo)
        start_time = Time.now.in_time_zone
        response = repository_api.get_repository_settings(id: repo.github_id)
        duration = Time.now.in_time_zone - start_time

        MetricsClient.distribution(
          "twirp.github.dependabot_repository_settings.get_repository_settings",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        raise NotFound, response.error.msg if response.error&.code == :not_found
        raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

        response.data
      end

      # rubocop:disable Naming/AccessorMethodName
      def set_paused_flag_on_repository(repo)
        start_time = Time.now.in_time_zone
        response = repository_api.set_paused_flag_on_repository(id: repo.github_id)
        duration = Time.now.in_time_zone - start_time

        MetricsClient.distribution(
          "twirp.github.dependabot_repository_settings.set_paused_flag_on_repository",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        raise NotFound, response.error.msg if response.error&.code == :not_found
        raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

        response.data
      end
      # rubocop:enable Naming/AccessorMethodName

      def remove_paused_flag_on_repository(repo)
        start_time = Time.now.in_time_zone
        response = repository_api.remove_paused_flag_on_repository(id: repo.github_id)
        duration = Time.now.in_time_zone - start_time

        MetricsClient.distribution(
          "twirp.github.dependabot_repository_settings.remove_paused_flag_on_repository",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

        response.data
      end

      # rubocop:disable Naming/AccessorMethodName
      def set_self_hosted_flag_on_repository(repo)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = repository_api.set_self_hosted_flag_on_repository(id: repo.github_id)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        MetricsClient.distribution(
          "twirp.github.dependabot_repository_settings.set_self_hosted_flag_on_repository",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        raise NotFound, response.error.msg if response.error&.code == :not_found
        raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

        log_if_actions_not_enabled(response, repo)

        response.data
      end
      # rubocop:enable Naming/AccessorMethodName

      private

      def log_if_actions_not_enabled(response, repo)
        return unless response.data&.success == false

        Dependabot::Logger.warn(
          msg: "Actions feature not enabled for the repo",
          "code.namespace": self.class.name.to_s,
          "gh.repo.id": repo.github_id,
        )
      end

      def repository_api
        @repository_api ||= MonolithTwirp::Dependabot::Settings::V1::RepositoryAPIClient.new(@client.connection)
      end
    end
  end
end
