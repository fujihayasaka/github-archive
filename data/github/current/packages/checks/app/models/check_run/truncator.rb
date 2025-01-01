# typed: true
# frozen_string_literal: true

require "truncatrix"

class CheckRun
  class Truncator
    def initialize(text)
      @text = text
      @truncated = false
    end

    def truncated?
      @truncated
    end

    def report_silent_truncation!(check_run:, repo:, integration:, type:)
      message = ""
      params = {
        github_app_id: integration.id,
        repo_id: repo.id,
        bytes_exceeded: truncatrix.bytes_exceeded,
        bytes_truncated: truncatrix.bytes_truncated,
        app: "github-tracing",
      }

      if check_run.persisted?
        message = "Truncated %d bytes from #{type} check run with id %d on repo with id %d" % [
          truncatrix.bytes_truncated,
          check_run.id,
          repo.id,
        ]
        params[:check_run_id] = check_run.id
      else
        message = "Truncated %d bytes from #{type} check run in check suite with id %d on repo with id %d" % [
          truncatrix.bytes_truncated,
          check_run.check_suite&.id,
          repo.id,
        ]
        params[:check_suite_id] = check_run.check_suite.id
      end

      boom = Api::CheckRuns::SilentTruncationError.new(message)
      Failbot.report!(boom, params)
    end

    def truncate
      return @text unless truncatrix.limit_exceeded?

      # Silently truncate here rather than in the database.
      # This avoids noisy needles in the github-slow-query bucket.
      @truncated = true
      truncated_text = truncatrix.truncated_text
    end

    private

    def truncatrix
      @truncatrix ||= Truncatrix.new(text: @text, limit: CheckRun::TEXT_BYTESIZE_LIMIT)
    end
  end
end
