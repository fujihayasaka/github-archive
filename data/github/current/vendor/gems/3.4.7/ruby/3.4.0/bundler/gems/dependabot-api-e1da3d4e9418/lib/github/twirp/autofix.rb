# frozen_string_literal: true

require "twirp"

module GitHub
  module Twirp
    class Autofix
      class Error < StandardError; end
      class NotFound < StandardError; end

      def initialize(client:)
        @client = client
      end

      def create_suggested_fix_annotation(autofix_job) # rubocop:disable Metrics/AbcSize
        start_time = Time.now.in_time_zone

        response = autofix_api.create_suggested_fix_annotation(
          repository_id: autofix_job.repo.github_id,
          pull_request_number: autofix_job.pull_request.github_number,
          autofix_job_id: autofix_job.id,
          check_run_id: autofix_job.check_run_id,
          annotation_location: annotation_location(autofix_job),
          level: autofix_job.level,
          message: autofix_job.message,
        )

        duration = Time.now.in_time_zone - start_time

        MetricsClient.distribution(
          "twirp.github.autofix_for_dependabot.create_suggested_fix_annotation",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        raise NotFound, response.error.msg if response.error&.code == :not_found
        raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

        response.data
      end

      private

      def annotation_location(autofix_job)
        location = autofix_job.dependency_declaration_location

        {
          file_path: location.fetch(:file_path),
          start_line: location.fetch(:start_line),
          end_line: location.fetch(:end_line),
          start_column: location.fetch(:start_column),
          end_column: location.fetch(:end_column),
        }
      end

      def autofix_api
        @autofix_api ||= MonolithTwirp::Dependabot::Settings::V1::AutofixAPIClient.new(@client.connection)
      end
    end
  end
end
