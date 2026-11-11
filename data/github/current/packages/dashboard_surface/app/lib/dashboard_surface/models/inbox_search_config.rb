# typed: strict
# frozen_string_literal: true

require "cgi"

module DashboardSurface
  module Models
    class InboxSearchConfig
      # Mapping of user-facing PR age option keys to day counts.
      # "none" means no PR age limit.
      PR_AGE_OPTIONS = T.let({
        "1m" => 30,
        "3m" => 90,
        "1y" => 365,
        "none" => nil,
      }.freeze, T::Hash[String, T.nilable(Integer)])

      DEFAULT_MAX_PR_AGE = "1m"

      sig { returns(T.untyped) }
      attr_reader :params

      sig { params(params: T.untyped, current_user: T.nilable(User)).returns(InboxSearchConfig) }
      def self.from_params(params, current_user = nil)
        new(params, current_user)
      end

      sig { params(params: T.untyped, current_user: T.nilable(User)).void }
      def initialize(params, current_user = nil)
        @params = params
        @current_user = current_user
        @search_config = T.let(SearchConfig.from_params(params), DashboardSurface::Models::SearchConfig)
      end

      sig { returns(T.nilable(DashboardSurface::Models::SearchConfig::NamedQuery)) }
      private def named_query_def
        # Direct lookup via SearchConfig (plain named queries like "needs-action")
        result = @search_config.named_query_def
        return result if result

        # Try extracting the named key from a suffix query (e.g. "needs-action repo:github/github")
        key = named_key_from_query
        return nil if key.nil?

        DashboardSurface::Models::SearchConfig::NAMED_QUERIES[key]
      end

      # Returns the sub-queries for a named/composite query (or a single-element
      # array for simple queries) with the age qualifier appended to each one
      # and repo scope if appended.
      sig { returns(T::Array[String]) }
      def es_queries
        named = named_query_def
        base_queries = named ? named.queries : [@search_config.es_query]
        suffix = named ? named_query_suffix : nil
        qualifier = age_qualifier

        base_queries.map do |query|
          q = suffix ? append_named_query_suffix(query, suffix) : query
          qualifier ? "#{q} #{qualifier}" : q
        end
      end

      # Returns true when the query requires multiple ES searches merged together.
      sig { returns(T::Boolean) }
      def composite?
        named = named_query_def
        return false if named.nil?

        named.queries.length > 1
      end

      # Returns the post-filter method name for this named query, or nil.
      sig { returns(T.nilable(Symbol)) }
      def post_filter
        named_query_def&.post_filter
      end

      sig { returns(Integer) }
      def maximum_result_limit
        @search_config.maximum_result_limit
      end

      sig { returns(Integer) }
      def page
        1
      end

      sig { returns(String) }
      def es_query
        named = named_query_def
        if named
          query = named.queries.first.to_s
          suffix = named_query_suffix
          query = append_named_query_suffix(query, suffix) if suffix
        else
          query = @search_config.es_query
        end

        qualifier = age_qualifier
        qualifier ? "#{query} #{qualifier}" : query
      end

      # Returns the section name if this is a named query, nil otherwise.
      sig { returns(T.nilable(String)) }
      def named_section
        key = named_key_from_query

        return key if key && DashboardSurface::Models::SearchConfig::NAMED_QUERIES.key?(key)

        nil
      end

      sig { returns(T.nilable(String)) }
      private def named_query_suffix
        query = named_query_input
        return nil if query.blank?

        tokens = query.split(/\s+/, 2)
        key = tokens.first.to_s
        suffix = tokens[1]
        return nil unless DashboardSurface::Models::SearchConfig::NAMED_QUERIES.key?(key)

        normalize_named_query_suffix(suffix)
      end

      sig { returns(String) }
      private def named_query_input
        query = params[:q].to_s.strip
        return query if query.blank?

        key = query.split(/[\s+]/, 2).first.to_s
        return query unless DashboardSurface::Models::SearchConfig::NAMED_QUERIES.key?(key)

        CGI.unescape(query)
      end

      sig { params(suffix: T.nilable(String)).returns(T.nilable(String)) }
      private def normalize_named_query_suffix(suffix)
        raw = suffix.to_s.strip
        return nil if raw.blank?

        # Only allow the `repo:` qualifier.
        parsed = ::Search::ParsedQuery.parse(raw, terms: [:repo], normalize_quotes: false)

        key_value_segments, raw_text_segments = parsed.partition { |seg| seg.is_a?(Array) }
        return nil if raw_text_segments.any? # disallow free text like "foo" or "repo:a/b OR"

        repo_values = T.let([], T::Array[String])
        key_value_segments.each do |seg|
          key, value, negated = T.cast(seg, T::Array[T.untyped])

          return nil unless key.to_sym == :repo
          return nil if negated

          v = value.to_s.strip
          return nil if v.blank?

          repo_values << v
        end

        repo_values.uniq!
        return nil if repo_values.empty?

        if repo_values.length == 1
          "repo:#{repo_values.first}"
        else
          repo_values.map { |v| "repo:#{v}" }.join(" OR ")
        end
      rescue => _e
        # If parsing fails for any reason, treat suffix as unsupported.
        nil
      end

      sig { params(query: String, suffix: String).returns(String) }
      private def append_named_query_suffix(query, suffix)
        if suffix.include?(" ") || suffix.start_with?("(")
          "#{query} (#{suffix})"
        else
          "#{query} #{suffix}"
        end
      end

      sig { returns(T.nilable(String)) }
      private def named_key_from_query
        query = named_query_input
        return nil if query.blank?

        tokens = query.split(/\s+/, 2)
        key = tokens.first.to_s
        suffix = tokens[1]
        return nil unless DashboardSurface::Models::SearchConfig::NAMED_QUERIES.key?(key)

        return key if suffix.blank?

        return nil if normalize_named_query_suffix(suffix).nil?

        key
      end

      # Returns the PR age option key for the current request.
      sig { returns(String) }
      def max_pr_age_key
        key = params_with_age_preference[:max_pr_age].to_s.strip.presence
        PR_AGE_OPTIONS.key?(key) ? key : DEFAULT_MAX_PR_AGE
      end

      # Returns the `created:>=YYYY-MM-DD` qualifier to append to ES queries,
      # or nil when there is no PR age limit.
      sig { returns(T.nilable(String)) }
      def age_qualifier
        days = PR_AGE_OPTIONS[max_pr_age_key]
        return nil if days.nil?

        cutoff = (Time.now.utc - days.days).to_date.iso8601
        "created:>=#{cutoff}"
      end

      private

      # Merges the user's persisted max_pr_age preference into the params
      # so that SearchConfig can read it.
      sig { returns(T.untyped) }
      def params_with_age_preference
        age_from_params = params[:max_pr_age].to_s.strip.presence
        return params if age_from_params

        user = @current_user
        return params unless user

        age_pref = user.settings.get(:pulls_inbox_max_pr_age)
        return params unless age_pref.present?

        params.respond_to?(:merge) ? params.merge(max_pr_age: age_pref) : params
      end
    end
  end
end
