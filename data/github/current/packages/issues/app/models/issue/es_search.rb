# typed: true
# frozen_string_literal: true

class Issue
  module EsSearch
    MAX_OFFSET = 10_000

    def self.search(query:, repo: nil, current_user: nil, remote_ip: nil, user_session: nil, force_pulls: false, page: 1, per_page: ApplicationController::DEFAULT_PER_PAGE, tags: [], **kargs)
      # Convert parsed query to String for ES
      # TODO: Search::Queries::IssueQuery should accept a parsed query
      if query.is_a?(Array)
        query = Search::Queries::IssueQuery.stringify(query)
      end

      unless query.is_a?(String)
        raise ArgumentError, "query must be a String: #{query.class}"
      end

      with_cursor_pagination = kargs[:use_cursor_pagination]

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
        after: kargs[:after],
        before: kargs[:before],
      }
      hash[:type] = "pr" if force_pulls
      hash[:sort] = %w[created desc] if !query.include?("sort:")
      if with_cursor_pagination
        if kargs[:last]
          hash[:last] = kargs[:last]
          hash.delete :per_page
        elsif kargs[:first]
          hash[:first] = kargs[:first]
          hash.delete :per_page
        end
      end

      # Bypass the ES result cap if there's a logged-in user.
      hash[:max_offset] = MAX_OFFSET if current_user

      type = detect_type(query)

      if query_specific_index?(type, current_user)
        hash[:index] = ::Elastomer::Indexes::Issues.by_type(type)
      end

      if kargs.key?(:ngram_title)
        hash[:ngram_title] = kargs[:ngram_title]
      end

      open_count, closed_count, issues, cursor = if !with_cursor_pagination
        search_result = ::Search::Queries::IssueQuery.new(hash).execute
        extract_results_and_counts(search_result, page, per_page)
      else
        search_result = ::Search::Queries::CursorPaginatedConditionalIssueQuery.new(hash).execute
        extract_cursor_paginated_results_and_counts(search_result)
      end

      {
        open_count: open_count,
        closed_count: closed_count,
        issues: issues,
        cursor: cursor,
        offset_error: false
      }
    rescue Search::Query::MaxOffsetError
      {
        open_count: 0,
        closed_count: 0,
        issues: [],
        cursor: cursor,
        offset_error: true
      }
    end

    def self.detect_type(query)
      types = query.scan(/[is|type]\:(\w*)/).flatten.select { |r| r == "issue" || r == "pr" }
      types.size == 1 ? types[0] : nil
    end

    def self.query_specific_index?(type, user)
      !!type && GitHub.flipper["search_specific_index_for_prs_and_issues"].enabled?(user)
    end

    sig do params(search_result: Search::Results[T.untyped], page: Integer, per_page: Integer)
      .returns([Integer, Integer, T::Array[Issue]])
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

    sig do params(search_result: Search::Responses::CursorPaginationResponse)
      .returns([Integer, Integer, T::Array[Issue], T::Hash[Symbol, T.nilable(String)]])
    end
    def self.extract_cursor_paginated_results_and_counts(search_result)
      open_count = closed_count = 0

      state_counts = search_result.state_counts
      if state_counts.present?
        open_count = state_counts["open"] || 0
        closed_count = state_counts["closed"] || 0
      end

      cursor = {
        next_cursor: T.let(nil, T.nilable(String)),
        prev_cursor: T.let(nil, T.nilable(String))
      }

      issues = search_result.results.map { |result| result["_model"] }
      cursor[:next_cursor] = search_result.end_cursor if search_result.has_next_page
      cursor[:prev_cursor] = search_result.start_cursor if search_result.has_previous_page

      [open_count, closed_count, issues, cursor]
    end
  end
end
