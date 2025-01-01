# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Newsroom
        module Schemas
          module HomePage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "title": "newsroomTemplateHomepage",
                "type": "object",
                "properties": {
                  "hero": { "type": "object" },
                  "heroBackgroundImage": { "type": "object" },
                  "heroStatistics": {
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 3,
                  },
                  "pressReleaseSectionIntro": { "type": "object" },
                  "pressReleaseSectionCards": { "type": "object" },
                  "reportsSectionCards": { "type": "object" },
                  "reportsSectionStatistics": {
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 3,
                  },
                  "inTheNewsSectionIntro": { "type": "object" },
                  "inTheNewsSectionCards": { "type": "object" },
                  "ctaBanner": { "type": "object" },
                },
                "required": %w[hero heroBackgroundImage heroStatistics pressReleaseSectionIntro pressReleaseSectionCards reportsSectionCards reportsSectionStatistics inTheNewsSectionIntro inTheNewsSectionCards ctaBanner],
              }
            end
          end
        end
      end
    end
  end
end
