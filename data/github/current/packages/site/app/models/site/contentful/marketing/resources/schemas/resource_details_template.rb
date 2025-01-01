# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Resources
        module Schemas
          module ResourceDetailsTemplate
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "title": "templateResourceDetails",
                "type": "object",
                "properties": {
                  "title": { "type": "string" },
                  "hero": { "type": "object" },
                  "featuredImage": { "type": "object" },
                  "excerpt": { "type": "object" },
                  "lede": { "type": "object" },
                  "body": { "type": "object" },
                  "form": { "type": "object" },
                  "tableOfContents": { "type": "boolean" },
                  "featuredCta": { "type": "object" },
                  "peopleLabel": { "type": "string" },

                  "people": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "fullName": { "type": "string" },
                        "position": { "type": "string" },
                        "photo": { "type": "object" },
                      },
                      "required": %w[fullName]
                    }
                  },
                  "topics": {
                    "type": "array",
                    "items": {
                      "type": "string",
                      "enum": [
                        "AI",
                        "Cloud",
                        "DevOps",
                        "GitHub Actions",
                        "GitHub Advanced Security",
                        "GitHub Enterprise",
                        "Innersource",
                        "Open Source",
                        "Security",
                        "Software Development"
                      ]
                    }
                  },
                  "relatedResources": {
                    "type": "array",
                    "size": { "min": 3, "max": 3 }
                  }
                },
                "required": %w[title]
              }
            end
          end
        end
      end
    end
  end
end
