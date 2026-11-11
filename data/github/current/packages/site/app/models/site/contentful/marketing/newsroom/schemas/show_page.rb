# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Newsroom
        module Schemas
          module ShowPage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "title": "templateResourcesArticle",
                "type": "object",
                "properties": {
                  "title": { "type": "string" },
                  "publishedDate": { "type": "string" },
                  "updatedDate": { "type": "string" },
                  "excerpt": { "type": "object" },
                  "lede": { "type": "object" },
                  "content": { "type": "object" },
                  "heroBackgroundImage": { "type": "object" },
                  "featuredCallToAction": { "type": "object" },
                  "ctaBanner": { "type": "object" },
                  "cards": { "type": "object" },
                  "faq": { "type": "object" },
                  "brand": { "type": "string" }
                },
                "required": %w[title publishedDate excerpt lede content]
              }
            end
          end
        end
      end
    end
  end
end
