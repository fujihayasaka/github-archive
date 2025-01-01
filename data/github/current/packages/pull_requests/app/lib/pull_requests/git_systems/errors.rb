# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module Errors
      extend T::Helpers
      extend T::Sig
      include Kernel

      sealed!

      class Timeout < T::Struct
        include Errors

        const :exception, Exception
      end

      class Outage < T::Struct
        extend T::Sig
        include Errors

        class Reason < T::Enum
          enums do
            BackendsDisagree = new(:backends_disagree)
            UnavailableServers = new(:unavailable_servers)
            RepositoryNetwork = new(:repository_network)
            ThreePhaseCommit = new(:three_phase_commit)
            RateLimited = new(:rate_limited)
            RefContention = new(:ref_contention)
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
