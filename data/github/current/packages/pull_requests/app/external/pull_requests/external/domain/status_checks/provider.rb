# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks
        module Provider
          extend T::Helpers

          include GitHub::Memoizer

          requires_ancestor { Object }

          sig { returns(PullRequests::External::Domain::StatusChecks) }
          memoize def status_checks_domain
            PullRequests::External::Domain::StatusChecks.new
          end
        end
      end
    end
  end
end
