# typed: true
# frozen_string_literal: true

# Used to test if a user has commented on the given issue_id
#
module Platform
  module Loaders
    class HasStatusCheckRollup < Platform::Loader
      def self.load(repository, commit_oid)
        self.for(repository).load(commit_oid)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(commit_oids)
        with_check_suites = CheckSuite.connection.select_values(check_suites_sql(commit_oids))
        without_check_suites = commit_oids - with_check_suites

        with_statuses = if without_check_suites.any?
          ::Statuses.domain.fetch_distinct_shas_from_statuses(repository_id: @repository.id, shas: without_check_suites)
        else
          []
        end

        with_check_suites_or_statuses = with_check_suites | with_statuses

        commit_oids.each_with_object({}) do |commit_oid, results|
          results[commit_oid] = with_check_suites_or_statuses.include?(commit_oid)
        end
      end

      def check_suites_sql(commit_oids)
        # NOTE: This should really query on `check_suites.hidden` to be 100% consistent with our behavior for
        # showing check status rollups. That column isn't indexed though and since this loader is only used to decide
        # whether or not we should try to fetch the rollup async, this is an acceptable tradeoff. If all of the check_suites
        # are hidden and there are no statuses for a commit, no rollup will be rendered.
        Arel.sql(<<~SQL, repo_id: @repository.id, commit_oids: commit_oids)
          SELECT DISTINCT head_sha
          FROM check_suites
          WHERE
            check_suites.repository_id = :repo_id
            AND head_sha IN (:commit_oids)
        SQL
      end
    end
  end
end
