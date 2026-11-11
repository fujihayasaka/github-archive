# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks
        module IPreloader
          extend T::Helpers

          requires_ancestor { Object }

          interface!

          sig { abstract.params(records: T::Enumerable[Status]).void }
          def preload_statuses(records); end

          sig { abstract.params(records: T::Enumerable[CombinedStatus::CheckRunAdapter]).void }
          def preload_check_runs(records); end
        end
      end
    end
  end
end
