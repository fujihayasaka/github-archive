# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        class Traverser
          JsonLikeType = T.type_alias { T::Hash[T.untyped, T.untyped] }

          sig { params(data: T.nilable(T::Hash[T.untyped, T.untyped])).void }
          def initialize(data)
            @data = T.let(data || {}, JsonLikeType)
          end

          # Expects the `@data` to have a `contentful_raw_json_response` key (which is the current
          # common pattern) or to be the raw JSON response itself (which is the preferred new pattern).
          sig { returns(JsonLikeType) }
          def contentful_response
            @data.fetch(:contentful_raw_json_response, @data)
          end

          sig { params(field: T.any(Symbol, String)).returns(T.untyped) }
          def get_field(field)
            value = fields.fetch(field.to_s, nil)

            if value.is_a?(Array)
              value.map { |entry| extract_value(entry) }
            else
              extract_value(value)
            end
          end

          sig { returns(JsonLikeType) }
          def fields
            items.first&.fetch("fields") || {}
          end

          sig { params(id: String, type: String).returns(T.nilable(JsonLikeType)) }
          def find_link(id, type: "Entry")
            includes.fetch(type, []).find do |item|
              item.dig("sys", "id") == id
            end
          end

          sig { returns(T::Array[JsonLikeType]) }
          def items
            contentful_response.fetch("items", []) || []
          end

          sig { returns(JsonLikeType) }
          def includes
            contentful_response.fetch("includes", {}) || {}
          end

          sig { returns(T::Array[JsonLikeType]) }
          def included_entries
            includes.fetch("Entry", [])
          end

          private

          sig { params(entry: T.untyped).returns(T.untyped) }
          def extract_value(entry)
            return entry unless entry.is_a?(Hash)

            if entry.dig("sys", "type") == "Link"
              id = entry.dig("sys", "id")
              type = entry.dig("sys", "linkType") || "Entry"
              find_link(id, type: type)
            else
              entry
            end
          end
        end
      end
    end
  end
end
