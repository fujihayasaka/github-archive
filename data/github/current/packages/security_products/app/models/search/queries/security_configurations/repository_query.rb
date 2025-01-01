# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityConfigurations
      class RepositoryQuery < Search::Queries::SecurityCenter::Base
        extend T::Sig

        QUALIFIER_CONFIGURATION = :configuration
        QUALIFIER_CONFIG_STATUS = :"config-status"
        QUALIFIER_FAILURE_REASON = :"failure-reason"
        QUALIFIER_TEAM = :team

        QUALIFIERS = [
          QUALIFIER_CONFIGURATION,
          QUALIFIER_CONFIG_STATUS,
          QUALIFIER_FAILURE_REASON,
          QUALIFIER_TEAM
        ].freeze

        class << self
          def parse_and_normalize(query)
            query_hash = parse(query)
            return query_hash if query_hash.empty?

            key = [QUALIFIER_CONFIG_STATUS, negate_qualifier(QUALIFIER_CONFIG_STATUS.to_s)].find { |k| query_hash.key?(k) }

            query_hash[self.literals_key].reject! { |key| key.start_with?("archived") }

            # TODO (allow-archived-repos): We filter out archived repos because it is not currently supported
            # by security configurations. This should be removed if that changes in the future.
            query_hash[self.literals_key] << "archived:false"

            query_hash
          end

          protected

          def allowed_qualifiers
            QUALIFIERS
          end

          def preserve_case
            true
          end
        end

        sig { params(query: String).void }
        def initialize(query: "")
          @query = query
          @query_hash = self.class.parse_and_normalize(query)
        end

        sig { returns(String) }
        def es_query_string
          @query_hash[self.class.literals_key].join(" ")
        end

        sig { returns(T::Hash[String, T::Array[T.untyped]]) }
        def mysql_query_hash
          @query_hash.except(self.class.literals_key)
        end
      end
    end
  end
end
