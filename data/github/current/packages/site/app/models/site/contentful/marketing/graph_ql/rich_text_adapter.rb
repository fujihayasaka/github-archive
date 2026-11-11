# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        class RichTextAdapter
          RichTextType = T.type_alias do
            {
              "nodeType" => String,
              "data" => T::Hash[String, T.untyped],
              "content" => T::Array[T.untyped],
            }
          end
          sig { params(data: T::Hash[String, T.untyped]).void }
          def initialize(data:)
            @data = data
          end

          sig { returns(T.nilable(RichTextType)) }
          def call
            rich_text_json = @data.fetch("json", {})

            return if rich_text_json.empty?

            {
              "nodeType" => rich_text_json["nodeType"],
              "data" => rich_text_json["data"],
              "content" => rich_text_json["content"],
            }
          end
        end
      end
    end
  end
end
