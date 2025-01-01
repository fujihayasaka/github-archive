# typed: true
# frozen_string_literal: true

class Issue
  module EsSearch
    def self.search(query:, repo: nil, current_user: nil, remote_ip: nil, user_session: nil, force_pulls: false, page: 1, per_page: ApplicationController::DEFAULT_PER_PAGE, tags: [], **kargs)
      # Convert parsed query to String for ES
      # TODO: Search::Queries::IssueQuery should accept a parsed query
      if query.is_a?(Array)
        query = Search::Queries::IssueQuery.stringify(query)
      end

      unless query.is_a?(String)
        raise ArgumentError, "query must be a String: #{query.class}"
      end

      hash = {
        phrase: query,
        repo_id: repo&.id,
        aggregations: :state,
        page: page,
        per_page: per_page,
        current_user: current_user,
        remote_ip: remote_ip,
        user_session: user_session,
        source_fields: false,
        context: kargs[:context] || "#{self.class.name&.demodulize.underscore}-#{__method__}",
      }
      hash[:type] = "pr" if force_pulls
      hash[:sort] = %w[created desc] if !query.include?("sort:")

      # Bypass the ES result cap if there's a logged-in user.
      hash[:max_offset] = 10_000 if current_user

      type = detect_type(query)

      if query_specific_index?(type, current_user)
        hash[:index] = ::Elastomer::Indexes::Issues.by_type(type)
      end

      if kargs.key?(:ngram_title)
        hash[:ngram_title] = kargs[:ngram_title]
      end

      search_result = ::Search::Queries::IssueQuery.new(hash).execute
      open_count, closed_count, issues = extract_results_and_counts(search_result, page, per_page)
      {
        open_count: open_count,
        closed_count: closed_count,
        issues: issues,
      }
    rescue Search::Query::MaxOffsetError
      {
        open_count: 0,
        closed_count: 0,
        issues: [],
      }
    end

    def self.detect_type(query)
      types = query.scan(/[is|type]\:(\w*)/).flatten.select { |r| r == "issue" || r == "pr" }
      types.size == 1 ? types[0] : nil
    end

    def self.query_specific_index?(type, user)
      !!type && GitHub.flipper["search_specific_index_for_prs_and_issues"].enabled?(user)
    end

    def self.extract_results_and_counts(search_result, page, per_page)
      open_count = closed_count = 0

      state_counts = search_result.state_counts
      if state_counts.present?
        open_count = state_counts["open"] || 0
        closed_count = state_counts["closed"] || 0
      end

      issues = WillPaginate::Collection.create(page, per_page, search_result.total) do |pager|
        pager.replace search_result.results.map { |result| result["_model"] }
      end

      [open_count, closed_count, issues]
    end
  end
end
