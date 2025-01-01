# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # This intentionally does not inherit from Search::Query because this query
    # is not executed by Elasticsearch, so we need different functionality than
    # usual from this class.
    class MemexProjectQuery
      extend T::Sig

      DEFAULT_QUERY = "is:open"
      VALID_STATES = %w(open closed template private public).freeze

      attr_reader :filters, :full_text_query_terms, :raw_query, :single_term_query

      def initialize(query)
        # Use an OrderedHash to preserve user-entered order of filters in `stringify`.
        @filters = ActiveSupport::OrderedHash.new
        @full_text_query_terms = []
        @raw_query = query&.strip || DEFAULT_QUERY
        @query_is_default = query.nil? || @raw_query == DEFAULT_QUERY

        term_query_filters = []
        was_last_token_qualifier = T.let(false, T::Boolean)
        @raw_query.split(/\s+/).each do |token|
          if token.include?(":")
            qualifier, value = token.split(":", 2)
            qualifier = "creator" if qualifier == "author" # Alias/normalize a common alternative.
            qualifier = qualifier.to_sym
            # is qualifier is unique because it can be repeated
            case qualifier
            when :is, :creator
              @filters[qualifier] ||= Set.new
              @filters[qualifier] << value
            else
              @filters[qualifier] = value
            end
            was_last_token_qualifier = true
          else
            @full_text_query_terms << token
            # If free text query is split by a qualifier eg "project is:open experience", reset the term query after the qualifier
            if was_last_token_qualifier
              term_query_filters.clear
            end

            term_query_filters << token
            was_last_token_qualifier = false
          end
        end

        # By default, project search uses the first term of full_text_query_terms to match on project titles
        # this is problematic for scenarios where we show a small subset of projects and the first term is too generic
        # to derive meaningful results.
        # Using term_query_filter performs a case-insentive match on the entire query string "projects experience"
        @single_term_query = term_query_filters.join(" ")
      end

      sig { returns(T::Boolean) }
      def state_filters?
        state_filters.any?
      end

      sig { returns(T::Array[String]) }
      def state_filters
        return @state_filters if defined?(@state_filters)
        @state_filters = if @filters[:is].present?
          normalized_state_filters = @filters[:is].map(&:downcase)
          (VALID_STATES & normalized_state_filters)
        else
          []
        end
      end

      # Returns true if state filter is only comprised of "is:open"
      # Optionally, remove the is:template filter from this check, to account for the
      # default query on the templates index page, which adds is:template by default
      sig { params(strip_template_filter: T::Boolean).returns(T::Boolean) }
      def default_open_filter?(strip_template_filter: false)
        state_filters_copy = state_filters.dup
        if strip_template_filter
          state_filters_copy.delete("template")
        end
        state_filters_copy == ["open"]
      end

      # Returns true if state filter is only comprised of "is:closed"
      # Optionally, remove the is:template filter from this check, to account for the
      # default query on the templates index page, which adds is:template by default
      sig { params(strip_template_filter: T::Boolean).returns(T::Boolean) }
      def default_closed_filter?(strip_template_filter: false)
        state_filters_copy = state_filters.dup
        if strip_template_filter
          state_filters_copy.delete("template")
        end
        state_filters_copy == ["closed"]
      end

      sig { returns(T::Boolean) }
      def only_template_filter?
        state_filters == ["template"]
      end

      sig { returns(T::Boolean) }
      def has_template_filter?
        state_filters.include?("template")
      end

      sig { returns(T::Set[String]) }
      def creator_filter
        @filters[:creator] ||= Set.new
      end

      sig { returns(T::Array[String]) }
      def sort_filter
        sort = if @filters[:sort].present? && valid_sort?(@filters[:sort])
          @filters[:sort]
        else
          MemexesHelper::DEFAULT_SORT
        end
        key, value = sort.split("-")

        [sort_field(key), value]
      end

      sig { params(key: String).returns(String) }
      def sort_field(key)
        if key == "created"
          "created_at"
        elsif key == "updated"
          "updated_at"
        else
          key
        end
      end

      sig { returns(T::Boolean) }
      def non_default_query?
        !@query_is_default
      end

      sig { returns(String) }
      def stringify
        return @stringified if defined?(@stringified)
        normalized_filters = @filters.reduce([]) do |memo, (qualifier, value)|
          if value.respond_to?(:each)
            value.each do |v|
              memo << "#{qualifier}:#{v}"
            end
          else
            memo << "#{qualifier}:#{value}"
          end
          memo
        end
        @stringified = (normalized_filters + full_text_query_terms).join(" ").strip
      end

      # creates a new search query by duplicating the current parsed query and then
      # applies any of the arguments to said duplicate, return
      sig { params(replace: T::Hash[Symbol, T.untyped]).returns(MemexProjectQuery) }
      def memex_project_query(replace: {})
        next_project_query = MemexProjectQuery.new(@raw_query)

        replace.each_pair do |key, value|
          if value
            next_project_query.filters[key] = value
          else
            next_project_query.filters.reject! { |k, _v| k == key }
          end
        end

        next_project_query
      end

      sig { params(sort: String).returns(T::Boolean) }
      def selected_projects_sort?(sort)
        return true if @filters[:sort].nil? && sort == MemexesHelper::DEFAULT_SORT
        @filters[:sort] == sort
      end

      sig { params(sort: String).returns(T::Boolean) }
      def valid_sort?(sort)
        MemexesHelper::SORTS.find do |_key, value|
          value == sort
        end.present?
      end
    end
  end
end
