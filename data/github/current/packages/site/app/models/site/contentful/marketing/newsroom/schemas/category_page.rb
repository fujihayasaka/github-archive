# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Newsroom
        module Schemas
          module CategoryPage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "title": "newsroomTemplateCategory",
                "type": "object",
                "properties": {
                  "hero": { "type": "object" },
                  "ctaBanner": { "type": "object" },
                },
                "required": %w[hero ctaBanner],
              }
            end
          end
        end
      end
    end
  end
end
