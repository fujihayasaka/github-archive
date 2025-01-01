# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestCheckReviews < Platform::Loader
      include Scientist

      def self.load(repository, pull_request, ref_update, open_pulls_only)
        self.for([repository, open_pulls_only]).load([pull_request, ref_update])
      end

      def initialize(options)
        @repository, @open_pulls_only = options
      end

      private

      attr_reader :repository

      def fetch(pr_ref_identifiers)
        results_by_head_sha = results_by_head_sha(pr_ref_identifiers)
        results_by_head_sha.default = []

        clean_and_prefill_results(pr_ref_identifiers, results_by_head_sha)
      end

      def results_by_head_sha(pr_ref_identifiers)
        prs, refs = pr_ref_identifiers.transpose
        head_shas = []
        head_shas = prs.map(&:head_sha)
        ref_names = refs.flat_map { |ref| base_ref_names_for_query(ref.refname) }.uniq

        pull_request_reviews_query_for(head_shas, ref_names)
      end

      def pull_request_reviews_query_for(head_shas, ref_names)
        sql = ::PullRequestReview.find_by_sql(Arel.sql(sql_query,
          repository_id: @repository.id,
          head_shas: head_shas,
          base_ref_names: ref_names,
          states: [
            ::PullRequestReview.state_value(:approved),
            ::PullRequestReview.state_value(:changes_requested),
            ::PullRequestReview.state_value(:dismissed),
          ],
        ))
        sql.group_by { |result| [result["base_ref"], result["head_sha"]] }
      end

      def sql_query
        # Group-wise maximum against id column rather than updated_at because
        # http://bugs.mysql.com/bug.php?id=54784
        <<-SQL
        SELECT r1.*, r2.head_sha, r2.base_ref
        FROM pull_request_reviews r1
        INNER JOIN
        (
          SELECT max(r3.id) as id, r3.pull_request_id, pull_requests.head_sha as head_sha, pull_requests.base_ref as base_ref
          FROM pull_request_reviews r3
          #{default_inner_query_clause}
          AND   r3.state IN (:states)
          GROUP BY r3.pull_request_id, pull_requests.head_sha, pull_requests.base_ref, r3.user_id
          ORDER BY NULL
        ) r2
        ON r1.id = r2.id
        ORDER BY r1.updated_at DESC
        SQL
      end

      def default_inner_query_clause
        if @open_pulls_only
          <<-SQL
          INNER JOIN pull_requests ON (pull_requests.id = r3.pull_request_id)
          INNER JOIN issues ON (issues.pull_request_id = pull_requests.id)
          WHERE pull_requests.repository_id = :repository_id
          AND   pull_requests.head_sha IN (:head_shas)
          AND   issues.state = 'open'
          AND   pull_requests.base_ref IN (:base_ref_names)
          SQL
        else
          <<-SQL
          INNER JOIN pull_requests ON (pull_requests.id = r3.pull_request_id)
          WHERE pull_requests.repository_id = :repository_id
          AND   pull_requests.head_sha IN (:head_shas)
          AND   pull_requests.base_ref IN (:base_ref_names)
          SQL
        end
      end

      def clean_and_prefill_results(pr_ref_identifiers, results_by_head_sha)
        results = Hash.new([])
        Promise.all(pr_ref_identifiers.map do |pr, ref|
          key = [pr, ref]
          reviews = results_by_head_sha[[pr.base_ref, pr.head_sha]]
          results[key] = reviews
          ::PullRequestReview::EnforcedLoader.new(
            repository: @repository,
            pull_request_head_sha: pr.head_sha,
            pull_request: pr,
            open_pulls_only: @open_pulls_only,
            writers_only: true,
            base_ref_name: ref.refname,
            ).async_clean_reviews(reviews)
        end).sync
        results
      end

      def base_ref_names_for_query(base_ref_name)
        Git::Ref.safe_ref_name(ref_names: base_ref_name).map { |ref| GitHub::SQL::ArelLiterals.binary(ref) }
      end
    end
  end
end
