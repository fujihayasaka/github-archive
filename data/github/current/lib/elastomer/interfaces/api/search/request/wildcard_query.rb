# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          # This models Elasticsearch "Wildcard Query" shapes. See the following documentation for more info:
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.14/query-dsl-wildcard-query.html
          class WildcardQuery < T::Struct
            extend T::Sig

            class Value
              extend T::Sig

              sig { params(value: String).void }
              def initialize(value)
                unless value.include?("*")
                  raise ArgumentError, "Wildcard queries must include at least one asterisk (*)"
                end
                @value = value
              end

              sig { returns(T::Hash[Symbol, T.untyped]) }
              def to_hash
                { value: @value }
              end
            end

            # Required
            const :field_path, String
            const :value, Value

            # Optional
            const :boost, T.nilable(Float), default: nil
            const :rewrite, T.nilable(String), default: nil
            const :case_insensitive, T.nilable(T::Boolean), default: false

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                wildcard: {
                  field_path => {
                    case_insensitive:,
                    boost:,
                    rewrite:,
                  }
                  .merge(value.to_hash)
                  .compact
                }
              }
            end
          end
        end
      end
    end
  end
end
