# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Solutions
        module Schemas
          module CategoryPage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                title: "solutionsTemplateCategory",
                type: "object",
                properties: {
                  title: { type: "string" },
                  hero: { type: "object" },
                  solutionPageCards: { type: "object" },
                  relatedSolutionCards: { type: "object" },
                  breakoutBanner: { type: "object" },
                  featuredStatistics: {
                    type: "array",
                    minItems: 3,
                    maxItems: 4,
                  },
                  ctaBanner: { type: "object" },
                },
                required: %w[title hero solutionPageCards ctaBanner],
              }
            end
          end
        end
      end
    end
  end
end
