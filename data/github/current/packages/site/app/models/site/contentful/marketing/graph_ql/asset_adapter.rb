# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        class AssetAdapter
          AssetType = T.type_alias do
            {
              "sys" => T::Hash[String, T.untyped],
              "fields" => AssetFields,
            }
          end

          AssetFields = T.type_alias do
            {
              "description" => T.nilable(String),
              "file" => T::Hash[String, T.untyped],
            }
          end

          sig do
            params(
              data: T::Hash[String, T.untyped] # The raw asset data from the GraphQL response
            ).void
          end
          def initialize(data:)
            @data = data
          end

          sig { returns(T.nilable(AssetType)) }
          def call
            return if @data.empty?

            {
              "sys" => {
                "id" => @data.dig("sys", "id"),
                "contentType" => {
                  "sys" => {
                    "id" => "Asset"
                  }
                }
              },
              "fields" => {
                "description" => @data["description"],
                "file" => {
                  "contentType" => @data["contentType"],
                  "url" => @data["url"],
                  "details" => {
                    "size" => @data["size"],
                    "image" => {
                      "width" => @data["width"],
                      "height" => @data["height"]
                    },
                  },
                }
              }
            }
          end
        end
      end
    end
  end
end
