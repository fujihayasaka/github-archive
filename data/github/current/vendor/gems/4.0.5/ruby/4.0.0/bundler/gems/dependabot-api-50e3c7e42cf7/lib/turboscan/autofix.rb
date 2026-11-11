# frozen_string_literal: true

require_relative "./client"

module Turboscan
  class Autofix
    class Error < StandardError; end

    def initialize(client: nil)
      @client = client || Client.new
    end

    def generate_dependabot_fix(autofix_job)
      start_time = Time.now.in_time_zone

      response = client.generate_dependabot_fix(
        request_id: autofix_job.id,
        repository_id: autofix_job.pull_request.repo.github_id,
        commit_oid: autofix_job.target_sha,
        sarif: autofix_job.sarif_content.to_json,
        file_paths: autofix_job.affected_file_paths,
      )

      duration = Time.now.in_time_zone - start_time

      MetricsClient.distribution(
        "twirp.turboscan.autofix_for_dependabot.generate_dependabot_fix",
        duration,
        tags: { response_code: response&.error&.code || :ok }
      )

      raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

      response.data
    end

    private

    attr_reader :client
  end
end
