# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        # Utility class to adapt a GraphQL entry response into the shape expected by the rest of the Contentful SDK.
        # This includes adding the `sys` and `fields` keys, as well as adapting nested entries and assets.
        class EntryAdapter
          EntryType = T.type_alias do
            {
              "sys" => T::Hash[String, T.untyped],
              "fields" => T::Hash[String, T.untyped],
            }
          end

          sig do
            params(
              typename: String, # The __typename of the entry. Crucial since the client validates this
              data: T::Hash[String, T.untyped] # The raw data of the entry from the GraphQL response
            ).void
          end
          def initialize(typename:, data:)
            @typename = typename
            @data = data
          end

          sig { returns(T.nilable(EntryType)) }
          def call
            return if @data.empty?

            {
              "sys" => {
                "id" => @data.dig("sys", "id"),
                "contentType" => {
                  "sys" => {
                    "id" => content_type_id
                  }
                }
              },
              "fields" => adapt_nested_fields
            }
          end

          sig do
            returns(String) # @typename with the first letter lowercased
          end
          def content_type_id
            "#{@typename[0]&.downcase}#{@typename[1..]}"
          end

          sig { returns(T::Hash[String, T.untyped]) }
          def adapt_nested_fields
            @data
              .except("__typename", "sys")
              .transform_values { |value| adapt_value(value) }
              .transform_keys { |key| key.to_s.sub(/Collection\z/, "") }
          end

          sig { params(value: T.untyped).returns(T.untyped) }
          def adapt_value(value)
            return value unless value.is_a?(Hash)

            if value.has_key?("items") && value["items"].is_a?(Array)
              value["items"].map { |item| adapt_value(item) }
            elsif value.has_key?("json")
              Site::Contentful::Marketing::GraphQL::RichTextAdapter.new(data: value).call
            elsif value.has_key?("__typename")
              if value["__typename"] == "Asset"
                Site::Contentful::Marketing::GraphQL::AssetAdapter.new(data: value).call
              else
                self.class.new(
                  typename: value["__typename"],
                  data: value.except("__typename")
                ).call
              end
            else
              value
            end
          end
        end
      end
    end
  end
end
