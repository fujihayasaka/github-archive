# typed: true
# frozen_string_literal: true

module Search
  module Queries

    class InstalledRepoQuery < RepoQuery

      DEFAULT_RESOURCE = "metadata"

      attr_reader :installation

      def initialize(opts = {}, &block)
        super(opts, &block)
        @installation = opts[:installation]
      end

      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}
        filters[:repo_id] = builder.repository_filter(
          current_user,
          repo_ids,
          DEFAULT_RESOURCE,
          user_session: user_session,
          ip: remote_ip
        )

        @filter_hash = filters
      end

      def repo_ids
        return [] if current_user.nil? || installation.nil?

        current_user.associated_installation_repository_ids(installation)
      end

      # Internal: By default, query only name, its variations
      # and name with owner.
      def query_fields
        return @query_fields if defined? @query_fields

        search_in << "name" if search_in.empty?
        super
      end

      sig do
        override
        .params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results))
        .returns(Search::Results[T.untyped])
      end
      def execute(skip_prune_results: false, results_class: Search::Results)
        # Without repositories filtered with :repo_id, no result is expected.
        return super unless filter_hash[:repo_id].global?

        GitHub.dogstats.increment(
          "search.query.no_installed_repos",
          tags: datadog_tags
        )

        Results.empty
      end

      def valid_query?
        return false unless super

        if escaped_query.empty?
          @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
          return false
        end

        true
      end

    end  # InstalledRepoQuery
  end  # Queries
end  # Search
