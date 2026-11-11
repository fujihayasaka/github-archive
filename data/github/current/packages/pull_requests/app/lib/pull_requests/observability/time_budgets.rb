# typed: strict
# frozen_string_literal: true

module PullRequests
  module Observability
    module TimeBudgets
      # Returns a hash of Datadog-style tags describing the current request's
      # time-budget state.  When the request is not budgeted the hash contains
      # only the `budgeted: false` flag; otherwise it includes remaining and
      # total window milliseconds.
      sig { returns(T::Hash[String, T.any(T::Boolean, Integer)]) }
      def self.remaining_time_budget_tags
        unless GitHub::RequestDurationManager.budgeted?
          return { "gh.request.time_budget.budgeted" => false }
        end

        remaining_ms = GitHub::RequestDurationManager.remaining_time_ms
        elapsed_ms = GitHub::RequestDurationManager.elapsed_time_ms

        {
          "gh.request.time_budget.budgeted" => true,
          "gh.request.time_budget.remaining_ms" => remaining_ms,
          "gh.request.time_budget.elapsed_ms" => elapsed_ms,
          "gh.request.time_budget.total_window_ms" => remaining_ms + elapsed_ms,
        }
      end
    end
  end
end
