# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # This loader is used to load all the pull request reviews associated with a particular pull request ID
    # Writers_only denotes whether or not we reject certain reviews that don't meet the writers permissions.
    # This copies the logic seen within the `EnforcedLoader` class.
    class PullRequestEnforcedReviews < Platform::Loader
      def self.load(pr, writers_only: true)
        self.for([pr.repository, writers_only]).load(pr)
      end

      def initialize(options)
        @repository, @writers_only = options
      end

      private

      attr_reader :repository

      def fetch(prs)
        pr_ids = prs.pluck(:id)
        sql = ::PullRequestReview.find_by_sql(Arel.sql(sql_query,
          repository_id: @repository.id,
          pull_request_ids: pr_ids,
          states: [
            ::PullRequestReview.state_value(:approved),
            ::PullRequestReview.state_value(:changes_requested),
            ::PullRequestReview.state_value(:dismissed),
          ],
        ))

        results_by_id = sql.group_by { |result| result["pull_request_id"] }
        results_by_id.default = []

        clean_and_prefill_results(prs, results_by_id)
      end

      # Pulls all the reviews associated with certain pull request IDs based on their 'latest' review
      # (determined by the MAX id)
      def sql_query
        # Group-wise maximum against id column rather than updated_at because
        # http://bugs.mysql.com/bug.php?id=54784
        <<-SQL
        SELECT r1.*
        FROM pull_request_reviews r1
        INNER JOIN
        (
          SELECT max(r3.id) as id
          FROM pull_request_reviews r3
          WHERE pull_request_id IN (:pull_request_ids)
          AND   r3.state IN (:states)
          GROUP BY r3.pull_request_id, r3.user_id
        ) r2
        ON r1.id = r2.id
        ORDER BY r1.updated_at DESC
        SQL
      end

      def clean_and_prefill_results(prs, results_by_id)
        results = Hash.new([])

        Promise.all(prs.map do |pr|
          reviews = results_by_id[pr.id]
          results[pr] = reviews
          ::PullRequestReview::EnforcedLoader.new(
            repository: @repository,
            pull_request: pr,
            writers_only: @writers_only,
            ).async_clean_reviews(reviews)
        end).sync
        results
      end
    end
  end
end
