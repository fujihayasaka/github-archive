# typed: true
# frozen_string_literal: true


module Site
  module Contentful
    module Marketing
      module Resources
        module Pages
          module Whitepapers
            module Schemas
              module ShowPage
                sig { returns(T::Hash[T.untyped, T.untyped]) }
                def self.build
                  {
                    "$schema": "http://json-schema.org/draft-04/schema#",
                    "title": "templateWhitepaper",
                    "type": "object",
                    "properties": {
                      "title": { "type": "string" },
                      "contentType": {
                        "type": "string",
                        "in": %w[Whitepaper Ebook]
                      },
                      "heading": { "type": "string" },
                      "publishedDate": { "type": "string" },
                      "featuredImage": { "type": "object" },
                      "excerpt": { "type": "object" },
                      "lede": { "type": "object" },
                      "body": { "type": "object" },
                      "form": { "type": "object" },
                      "downloadableAsset": { "type": "object" },
                      "downloadableAssetUrl": { "type": "string" },
                      "downloadableAssetCta": { "type": "string" },
                      "confirmationCtaDescription": { "type": "string" },
                      "relatedResources": {
                        "type": "array",
                        "size": { "min": 3, "max": 3 }
                    },
                      "topics": {
                        "type": "array",
                        "in": [
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
                    "required": %w[title contentType heading publishedDate excerpt lede body form topics]
                  }
                end
              end
            end
          end
        end
      end
    end
  end
end
