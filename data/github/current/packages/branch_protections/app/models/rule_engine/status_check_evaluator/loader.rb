# typed: true
# frozen_string_literal: true

module RuleEngine
  class StatusCheckEvaluator
    # Responsible for loading reported status check results (either `Status` or
    # `CheckRun` records) for a given repo and set of commit OIDs, and
    # optionally a set of contexts.
    class Loader
      include GitHub::Memoizer

      sig do
        params(
          repository: Repositories::IRepository,
          commit_oids: T::Array[String],
          contexts: T.nilable(T::Array[String]),
        ).void
      end
      def initialize(repository:, commit_oids:, contexts: nil)
        @repository = repository
        @commit_oids = commit_oids
        @contexts = contexts
      end

      sig { returns(T::Array[String]) }
      attr_reader :commit_oids

      sig { returns(Result) }
      memoize def checks
        Result.new(find_status_checks)
      end

      private

      sig { returns(T::Array[T.any(Status, CombinedStatus::CheckRunAdapter)]) }
      def find_status_checks
        return [] if @commit_oids.empty?
        find_commit_statuses + find_check_runs
      end

      sig { returns(T::Array[Status]) }
      def find_commit_statuses
        if @contexts.nil?
          statuses = Statuses.domain.current_statuses_for_shas(
            repository_id: @repository.id,
            shas: @commit_oids,
          )
        else
          statuses = Statuses.domain.current_statuses_for_contexts_and_shas(
            repository_id: @repository.id,
            contexts: @contexts,
            shas: @commit_oids,
          )
        end

        GitHub::PrefillAssociations.prefill_associations(statuses, [:creator])
        GitHub::PrefillAssociations.prefill_associations(statuses.map(&:creator).filter { |c| c.is_a?(Bot) }, [:integration])
        statuses.to_a
      end

      sig { returns(T::Array[CombinedStatus::CheckRunAdapter]) }
      def find_check_runs
        check_runs = Checks.domain.check_runs.prefetch(
          Checks.domain.check_runs.latest_for_shas(@commit_oids, repository_id: T.must(@repository.id)).values.flatten.sort_by(&:id),
          [:check_suite]
        )
        check_runs.map { |check_run| CombinedStatus::CheckRunAdapter.new(check_run) }
      end
    end
  end
end
