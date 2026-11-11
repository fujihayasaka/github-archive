# frozen_string_literal: true

require_relative "client"

module DependencyGraph
  class Snapshots
    class Error < StandardError; end
    class InvalidSnapshotError < Error; end

    def initialize(client: nil)
      @client = client || Client.new
    end

    def create_dependabot_snapshot(gh_repo_id:, payload:)
      request = Github::DependencySnapshotsApi::CreateDependabotSnapshotRequest.new(
        repository_id: gh_repo_id,
        payload: payload,
      )

      validate!(request)

      start_time = Time.now.in_time_zone
      response = client.create_dependabot_snapshot(request)
      duration = Time.now.in_time_zone - start_time

      MetricsClient.distribution(
        "twirp.dependency_graph.snapshots.create_dependabot_snapshot",
        duration,
        tags: { response_code: response&.error&.code || :ok }
      )

      # Handle Twirp::Error
      raise Error, "#{response.error.code} - #{response.error.msg}" if response.error

      handle_snapshot_response(response)
    end

    private

    attr_reader :client

    def handle_snapshot_response(response)
      case response.data.result
      when :RESULT_INVALID
        raise InvalidSnapshotError, response.data.message
      when :RESULT_ACCEPTED, :RESULT_SUCCESS
        true
      else
        raise Error, "unexpected snapshot response: '#{response.data.result}' - #{response.data.message}"
      end
    end

    def validate!(request)
      # The service will consider a zero value for version to be missing but in
      # the Ruby encoding this issue isn't caught by default.
      #
      # This can only happen as a result of programmer error in core.
      raise InvalidSnapshotError, "payload.version cannot be 0" if request.payload.version.zero?

      true
    end
  end
end
