# typed: strict
# frozen_string_literal: true

module PullRequests
  module Observability
    class Git
      sig do
        type_parameters(:T).
        params(
          rpc: Symbol,
          action: T.nilable(Symbol),
          pull_request_id: T.nilable(Integer),
          pull_request_number: T.nilable(Integer),
          repository_id: T.nilable(Integer),
          block: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
      end
      def self.measure(rpc:, action: nil, pull_request_id: nil, pull_request_number: nil, repository_id: nil, &block)
        start_time = GitHub::Dogstats.monotonic_time
        result = block.call
        duration = GitHub::Dogstats.duration(start_time)

        GitHub.dogstats.distribution(
          "pull_requests.git.duration",
          duration,
          tags: ["rpc:#{rpc}"],
        )

        GitHub.logger.info(
          "gh.git.rpc": rpc,
          "gh.git.action": action,
          "gh.pull_request.id": pull_request_id,
          "gh.pull_request.number": pull_request_number,
          "gh.repo.id": repository_id,
          "gh.git.rpc.duration": duration,
        )

        result
      end
    end
  end
end
