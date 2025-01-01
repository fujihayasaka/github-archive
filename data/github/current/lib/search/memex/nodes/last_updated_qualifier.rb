# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # This class implements support for the legacy `last-updated` qualifier, which has different syntax from
      # the preferred `updated` qualifier.
      class LastUpdatedQualifier < Qualifier
        extend T::Sig

        RANGE_REGEX = /\A(?<days>\d+)days?\z/

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          match = values.first&.match(RANGE_REGEX)
          return {} unless match

          now = Time.now.in_time_zone(context.viewer&.time_zone)
          target_date = (now - match[:days].to_i.days).strftime("%Y-%m-%d")
          date_range_query = Elastomer::Interfaces::Api::Search::Request::RangeQuery.new(
            field_path: "updated_at",
            operators: Elastomer::Interfaces::Api::Search::Request::RangeQuery::Operators.new(
              negated? ? { gt: target_date } : { lte: target_date }
            )
          )

          {
            bool: {
              filter: date_range_query.to_hash
            }
          }
        end
      end
    end
  end
end
