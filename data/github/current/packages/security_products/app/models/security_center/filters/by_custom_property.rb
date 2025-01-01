# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Filters
    class ByCustomProperty
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      LIMIT = 10_000

      instrument_method(:apply)

      sig { returns(String) }; attr_reader :query
      sig { returns(::Organization) }; attr_reader :org
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids

      sig { params(query: String, org: ::Organization, allowed_repo_ids: T.nilable(T::Array[Integer])).void }
      def initialize(query:, org:, allowed_repo_ids: nil)
        @query = query
        @org = org
        @allowed_repo_ids = allowed_repo_ids
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        return rel if allowed_repo_ids&.empty?
        return rel if custom_properties.blank?

        rel.where(repository_id: es_repo_ids)
      end

      sig { returns(T::Boolean) }
      def is_empty?
        custom_properties.blank?
      end

      sig { returns(T::Boolean) }
      def has_incl_filters?
        T.cast(query.present?, T::Boolean) && !query.start_with?("-")
      end

      private

      sig { returns(T::Hash[String, T::Array[String]]) }
      memoize def custom_properties
        ::Search::Queries::SecurityCenter::QueryParser.new(query).custom_properties
      end

      sig { returns(T::Array[Integer]) }
      memoize def es_repo_ids
        es_query = Search::Queries::RepoQuery.new(
          binary_fork_filter: true,
          include_forks: true,
          normalizer: lambda { |hits| hits.map { |hit| hit.fetch("_source").fetch("repo_id") } },
          page: 1,
          per_page: LIMIT,
          phrase: ::Search::Queries::SecurityCenter::QueryParser.new(query).custom_properties_string,
          sort: %w(updated desc),
          source_fields: ["repo_id"],
          skip_permission_check: true,
        )
        es_query.qualifiers[:org].clear.must(org.display_login)
        es_query.qualifiers[:user].clear
        es_query.qualifiers[:owner].clear
        es_query.qualifiers[:repo].clear

        GitHub.tracer.in_span("security_center.filters.by_custom_property.es_repo_ids", kind: :internal) do
          GitHub.dogstats.distribution_time("security_center.filters.by_custom_property.es_repo_ids") do
            ids = es_query.execute(skip_prune_results: true).results

            ids &= T.must(allowed_repo_ids) unless allowed_repo_ids.nil?
            ids.sort
          end
        end
      end
    end
  end
end
