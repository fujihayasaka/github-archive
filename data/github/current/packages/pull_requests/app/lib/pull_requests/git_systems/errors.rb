# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module Errors
      extend T::Helpers

      include Kernel

      sealed!

      class Timeout < T::Struct
        include Errors

        const :exception, Exception
      end

      class Outage < T::Struct
        include Errors

        class Reason < T::Enum
          enums do
            BackendsDisagree = new(:backends_disagree)
            MalformedResponse = new(:malformed_response)
            RateLimited = new(:rate_limited)
            RefContention = new(:ref_contention)
            RepositoryNetwork = new(:repository_network)
            ThreePhaseCommit = new(:three_phase_commit)
            UnavailableServers = new(:unavailable_servers)
          end
        end

        const :reason, Reason
        const :exception, Exception
      end

      class Fatal < T::Struct
        include Errors

        const :exception, Exception
      end
    end
  end
end
