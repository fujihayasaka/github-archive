# typed: true
# frozen_string_literal: true

class PullRequestReview
  class EnforcedLoader
    def initialize(repository:, pull_request: nil, pull_request_head_sha: nil,
        base_ref_name: nil, writers_only: false, open_pulls_only: false, exclude_drafts: false)
      if [pull_request, pull_request_head_sha && base_ref_name].all?(&:blank?)
        raise ArgumentError, "either pull_request or (pull_request_head_sha && base_ref_name) must be present"
      end

      @repository = repository
      @pull_request = pull_request
      @pull_request_head_sha = pull_request_head_sha
      @writers_only = writers_only
      @open_pulls_only = open_pulls_only
      @base_ref_name = base_ref_name
      @exclude_drafts = exclude_drafts
    end

    # Public: Returns a list of the most recent review that each user has left,
    # as long as the review's status is approved or rejected.
    #
    # Includes dismissed in the query so that we can filter those out after.
    # This is so that we consider a most recent review which is dismissed
    # to be essentially ignored in the merge area.
    #
    # Returns Array of PullRequestReviews
    def execute
      load_reviews.tap do |reviews|
        async_clean_reviews(reviews).sync
      end
    end

    def async_clean_reviews(reviews)
      prefill_pull_request(reviews)
      reviews.reject!(&:dismissed?)
      if writers_only
        async_select_writers_only!(reviews)
      else
        Promise.resolve(reviews)
      end
    end

    private

    attr_reader :repository, :pull_request, :pull_request_head_sha,
                :writers_only, :open_pulls_only, :base_ref_name, :exclude_drafts

    def load_reviews
      PullRequestReview.find_by_sql(Arel.sql(sql_query,
        repository_id: repository.id,
        head_sha: pull_request_head_sha,
        pull_request_id: pull_request&.id,
        base_ref_names: base_ref_name ? base_ref_names_for_query : nil,
        states: [
          PullRequestReview.state_value(:approved),
          PullRequestReview.state_value(:changes_requested),
          PullRequestReview.state_value(:dismissed),
        ],
      )).group_by { |m| [m.pull_request_id, m.user_id] }
        .values
        .map! { |reviews| reviews.max_by { |review| review.id } }
        .sort! { |a, b| b.updated_at <=> a.updated_at }
    end

    def async_select_writers_only!(reviews)
      Promise.all(reviews.map do |review|
        review.async_author_can_push_to_repository?.then do |made_by_writer|
          [review, made_by_writer]
        end
      end).then do |reviews_writer_array|
        r = reviews_writer_array.to_h
        reviews.select! { |review| r[review] }
        reviews
      end
    end

    def base_ref_names_for_query
      base_ref = Git::Ref.safe_ref_name(ref_names: base_ref_name)
      base_ref.map { |ref| GitHub::SQL::ArelLiterals.binary(ref) }
    end

    def sql_query
      <<-SQL
        SELECT r1.*
        FROM pull_request_reviews r1
        #{lookup_query_clause}
        AND r1.state IN (:states)
        ORDER BY r1.updated_at DESC
      SQL
    end

    def lookup_query_clause
      if pull_request_head_sha
        head_sha_query_clause
      else
        <<-SQL
          WHERE pull_request_id = :pull_request_id
        SQL
      end
    end

    def head_sha_query_clause
      sql = if open_pulls_only
        <<-SQL
          INNER JOIN pull_requests ON pull_requests.id = r1.pull_request_id
          INNER JOIN issues ON issues.pull_request_id = r1.pull_request_id
          WHERE pull_requests.repository_id = :repository_id
          AND   pull_requests.head_sha = :head_sha
          AND  	issues.state = 'open'
          AND   pull_requests.base_ref IN (:base_ref_names)
        SQL
      else
        <<-SQL
          INNER JOIN pull_requests ON pull_requests.id = r1.pull_request_id
          WHERE pull_requests.repository_id = :repository_id
          AND   pull_requests.head_sha = :head_sha
          AND   pull_requests.base_ref IN (:base_ref_names)
        SQL
      end
      sql += " AND pull_requests.work_in_progress = false" if exclude_drafts
      sql
    end

    # Prefill pull request on every review so it isn't loaded by each review
    # when select_writers_only! is called
    def prefill_pull_request(reviews)
      return unless pull_request

      # Check ID since reviews may be loaded by head SHA instead of pull request ID
      reviews_to_prefill = reviews.select { |review| review.pull_request_id == pull_request.id }
      GitHub::PrefillAssociations.prefill_associations(reviews_to_prefill, :pull_request, available_records: [pull_request])
    end
  end
end
