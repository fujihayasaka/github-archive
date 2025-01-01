# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Solutions
        module Schemas
          module ShowPage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                title: "solutionsTemplateDetail",
                type: "object",
                properties: {
                  title: { type: "string" },
                  hero: { type: "object" },
                  introSectionContent: { type: "object" },
                  logoSuite: { type: "object" },
                  featuresSectionRivers: {
                    type: "array",
                    minItems: 3,
                    maxItems: 6,
                  },
                  featuresSectionRiversRiverStoryScroll: { type: "boolean" },
                  ctaBanner: { type: "object" },
                  resources: { type: "object" },
                  faq: { type: "object" },
                  testimonial: { type: "object" },
                  featuredCustomerStories: { type: "object" },
                  featuredCustomerBento: { type: "object" },
                  breakoutBanner: { type: "object" },
                  statistics:  {
                    type: "array",
                    minItems: 3,
                    maxItems: 3,
                  },
                },
                required: %w[title hero introSectionContent ctaBanner],
              }
            end
          end
        end
      end
    end
  end
end
