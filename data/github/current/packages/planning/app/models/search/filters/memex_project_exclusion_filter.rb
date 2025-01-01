# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # This class implements a filter that helps us exclude issues (and pull
    # requests) that are already referenced in a given MemexProject from search
    # results returned by a query against the issues index.
    class MemexProjectExclusionFilter < ::Search::Filter
      def initialize(opts = {})
        super(opts)

        @field = :issue_id
        @memex_project_id = opts.fetch(:memex_project_id, nil)
        @repository_id = opts.fetch(:repository_id, nil)
      end

      # Override unnecessary methods of superclass to be no-ops.
      def build(values); end
      def must; end
      def should; end

      # This filter is only used when needed, so it will never be blank.
      def blank?
        false
      end

      # Implement the only filter we actually need.
      def must_not
        build_term_filter(field, bool_collection.must_not)
      end

      # Builds up the exclusion clause for issues referenced in a given memex.
      def bool_collection
        return @bool_collection if defined? @bool_collection

        @bool_collection = ::Search::ParsedQuery::BoolCollection.new
        @bool_collection.must_not(issue_ids_to_exclude)
        @bool_collection.must_not.uniq! if @bool_collection.must_not?

        @bool_collection
      end

      private

      # Returns Array<Integer> for all the issue IDs that should be excluded
      # from the search results because they are already referenced in the memex.
      def issue_ids_to_exclude
        items = MemexProjectItem
          .select(:content_type, :content_id)
          .where(
            memex_project_id: @memex_project_id,
            repository_id: @repository_id,
            content_type: %w[Issue PullRequest]
          )
          .all

        issue_ids, pull_request_ids = items
          .partition { |i| i.content_type == "Issue" }
          .map { |collection| collection.map(&:content_id) }

        pull_request_issue_ids = Issue.where(pull_request_id: pull_request_ids).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        T.must(issue_ids) + pull_request_issue_ids
      end
    end
  end
end
