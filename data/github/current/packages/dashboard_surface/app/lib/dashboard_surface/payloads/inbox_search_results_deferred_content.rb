# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    class InboxSearchResultsDeferredContent
      class StatusCheckState < T::Enum
        enums do
          Success = new("SUCCESS")
          Failure = new("FAILURE")
          Pending = new("PENDING")
        end

        sig { params(state: T.nilable(String)).returns(T.nilable(StatusCheckState)) }
        def self.from_combined_state(state)
          return nil if state.nil?

          try_deserialize(state.upcase)
        end
      end

      class ReviewDecisionState < T::Enum
        enums do
          Approved = new("APPROVED")
          ChangesRequested = new("CHANGES_REQUESTED")
          ReviewRequired = new("REVIEW_REQUIRED")
        end

        sig { params(decision: T.nilable(Symbol)).returns(T.nilable(ReviewDecisionState)) }
        def self.from_review_decision(decision)
          return nil if decision.nil?

          try_deserialize(decision.to_s.upcase)
        end
      end

      class StatusCheckRollup < T::Struct
        const :state, T.nilable(StatusCheckState)
        const :totalCount, Integer
        const :successCount, Integer
      end

      class PullRequestDeferredResult < T::Struct
        const :id, Integer
        const :reviewDecisionState, T.nilable(ReviewDecisionState)
        const :statusCheckRollup, T.nilable(StatusCheckRollup)
      end

      sig { params(results: DashboardSurface::Loaders::ResultsLoader::DeferredData).void }
      def initialize(results)
        @results = results
      end

      sig { params(results: DashboardSurface::Loaders::ResultsLoader::DeferredData).returns(T.untyped) }
      def self.serialize(results)
        new(results).serialize
      end

      sig { returns({ results: T::Array[PullRequestDeferredResult] }) }
      def serialize
        {
          results: @results.pull_requests.map do |pr|
            combined_status = @results.combined_statuses[pr.id]
            success_count, total_count = parse_status_count(combined_status&.short_text)

            PullRequestDeferredResult.new(
              id: pr.id,
              reviewDecisionState: ReviewDecisionState.from_review_decision(@results.review_decisions[pr.id]),
              statusCheckRollup: if combined_status
                                   StatusCheckRollup.new(
                                     state: StatusCheckState.from_combined_state(combined_status.state),
                                     successCount: T.must(success_count),
                                     totalCount: T.must(total_count),
                                   )
                                 else
                                   nil
                                 end,
            )
          end,
        }
      end

      sig { params(short_text: T.nilable(String)).returns(T::Array[Integer]) }
      private def parse_status_count(short_text)
        return [0, 0] if short_text.nil?

        if short_text =~ /(\d+)\s*\/\s*(\d+)/
          success_count = Regexp.last_match(1).to_i
          total_count = Regexp.last_match(2).to_i
          [success_count, total_count]
        else
          [0, 0]
        end
      end
    end
  end
end
