# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # This loader is an attempt to improve the batch-ability of the PullRequestEnforcedReviews loader.
    # The other loader can only batches by repository, but this loader can batch pull requests from multiple
    # repositories into a single query.

    class PullRequestEnforcedReviewsCandidate < Platform::Loader
      def self.load(pr, writers_only: true)
        self.for.load([pr, { writers_only: writers_only }])
      end

      private

      def fetch(prs_and_options)
        prs = prs_and_options.map(&:first)
        pr_ids = prs.pluck(:id)
        repository_ids = prs.pluck(:repository_id).uniq

        results = track_time(pr_ids, repository_ids) do
          ::PullRequestReview.find_by_sql(Arel.sql(sql_query,
            pull_request_ids: pr_ids,
            repository_ids: repository_ids,
            states: [
              ::PullRequestReview.state_value(:approved),
              ::PullRequestReview.state_value(:changes_requested),
              ::PullRequestReview.state_value(:dismissed),
            ],
          ))
        end

        results_by_id = results.group_by { |result| result["pull_request_id"] }
        results_by_id.default = []

        clean_and_prefill_results(prs_and_options, results_by_id)
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
            AND r3.state IN (:states)
          GROUP BY r3.pull_request_id, r3.user_id
        ) r2
        ON r1.id = r2.id
        WHERE r1.repository_id IN (:repository_ids)
        ORDER BY r1.updated_at DESC
        SQL
      end

      def clean_and_prefill_results(prs_and_options, results_by_id)
        Promise.all(prs_and_options.map do |pr, options|
          writers_only = options[:writers_only]
          reviews = results_by_id[pr.id]

          pr.async_repository.then do
            ::PullRequestReview::EnforcedLoader.new(
              repository: pr.repository,
              pull_request: pr,
              writers_only: writers_only,
              ).async_clean_reviews(reviews).then do |clean_reviews|
                [[pr, options], clean_reviews]
              end
          end
        end).then do |prs_options_reviews|
          prs_options_reviews.each_with_object({}) do |(pr_and_options, reviews), results_by_pr|
            results_by_pr[pr_and_options] = reviews
          end
        end
      end

      def track_time(pr_ids, repository_ids)
        tags = {
          number_of_prs: number_range(pr_ids.length),
          number_of_repositories: number_range(repository_ids.length)
        }

        GitHub.dogstats.distribution_time("pull_requests.enforced_reviews.cross_repo.dist.duration", tags: tags) do
          yield
        end
      end

      def number_range(number)
        if number <= 10
          :from_1_to_10
        elsif number <= 100
          :from_11_to_100
        elsif number <= 1000
          :from_101_to_1000
        elsif number <= 10000
          :from_1001_to_10000
        else
          :above_10000
        end
      end
    end
  end
end
