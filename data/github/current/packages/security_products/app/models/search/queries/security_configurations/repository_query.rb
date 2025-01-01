# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityConfigurations
      class RepositoryQuery < Search::Queries::SecurityCenter::Base

        QUALIFIER_CONFIGURATION = :configuration
        QUALIFIER_CONFIG_STATUS = :"config-status"
        QUALIFIER_FAILURE_REASON = :"failure-reason"
        QUALIFIER_TEAM = :team
        QUALIFIER_ADVANCED_SECURITY = :"advanced-security"
        QUALIFIER_CODE_SCANNING = :"code-scanning-alerts"
        QUALIFIER_CODE_SCANNING_DEFAULT_SETUP = :"code-scanning-default-setup"
        QUALIFIER_DEPENDABOT_ALERTS = :"dependabot-alerts"
        QUALIFIER_DEPENDABOT_SECURITY_UPDATES = :"dependabot-security-updates"
        QUALIFIER_SECRET_SCANNING = :"secret-scanning-alerts"
        QUALIFIER_SECRET_SCANNING_PUSH_PROTECTION = :"secret-scanning-push-protection"

        ADVANCED_FILTER_QUALIFIERS = [
          QUALIFIER_ADVANCED_SECURITY,
          QUALIFIER_CODE_SCANNING,
          QUALIFIER_CODE_SCANNING_DEFAULT_SETUP,
          QUALIFIER_DEPENDABOT_ALERTS,
          QUALIFIER_DEPENDABOT_SECURITY_UPDATES,
          QUALIFIER_SECRET_SCANNING,
          QUALIFIER_SECRET_SCANNING_PUSH_PROTECTION,
        ].freeze

        QUALIFIERS = [
          QUALIFIER_CONFIGURATION,
          QUALIFIER_CONFIG_STATUS,
          QUALIFIER_FAILURE_REASON,
          QUALIFIER_TEAM,
          *ADVANCED_FILTER_QUALIFIERS,
        ].freeze


        class << self
          def parse_and_normalize(query, include_archived_repos: false)
            query_hash = parse(query)
            return query_hash if query_hash.empty?

            unless include_archived_repos
              query_hash[self.literals_key] << "archived:false"
            end

            combine_advanced_filters(query_hash)

            query_hash
          end

          protected

          def allowed_qualifiers
            QUALIFIERS + [Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT]
          end

          def preserve_case
            true
          end

          def combine_advanced_filters(query_hash)
            advanced_filters = []
            query_hash.each do |key, values|
              regular_qualifier = key.start_with?(negated_qualifier_prefix) ? key[1..-1] : key
              next unless ADVANCED_FILTER_QUALIFIERS.include?(regular_qualifier.to_sym)

              query_hash.delete(key)

              values.map! { |v| v == "disabled" ? "not-enabled" : v }
              advanced_filters << "#{key}:#{values.join(",")}"
            end

            query_hash["advanced_filters"] = advanced_filters.join(" ") if advanced_filters.any?
          end
        end

        sig { params(query: String, include_archived_repos: T::Boolean).void }
        def initialize(query: "", include_archived_repos: false)
          @query = query
          @query_hash = self.class.parse_and_normalize(query, include_archived_repos:)
        end

        # Returns the only the qualifers that are handled by ES
        # Currently, these are qualifiers like `visibility`, `fork,`, `archived`, etc.
        # Since these qualifers aren't added to the `allowed_qualifiers` method, they are collected into the
        # literals_key array in the query_hash.
        #
        # For repository properties, which are handled by ES, we added them to the `allowed_qualifiers` to properly
        # handle properties values that contain spaces. Therefore we need to collect them from the query_hash and
        # return them in this method.
        #
        # Note that a search qualifer should only be handled by ES or MySQL, not both.
        sig { returns(String) }
        def es_query_string
          es_query_hash = @query_hash.select { |k, _| self.class.literals_key == k || Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX.match(k) }

          self.class.to_s(es_query_hash)
        end

        # Returns the only the qualifers that are handled by MySQL
        sig { returns(T::Hash[String, T::Array[T.untyped]]) }
        def mysql_query_hash
          @query_hash.reject { |k, _| self.class.literals_key == k || Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX.match(k) }
        end
      end
    end
  end
end
