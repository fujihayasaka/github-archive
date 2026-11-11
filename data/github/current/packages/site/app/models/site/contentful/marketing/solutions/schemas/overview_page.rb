# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Solutions
        module Schemas
          module OverviewPage
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                title: "solutionsTemplateOverview",
                type: "object",
                properties: {
                  title: { type: "string" },
                  hero: { type: "object" },
                  heroBackgroundImage: { type: "object" },
                  companySizeSectionIntro: { type: "object" },
                  companySizeSectionSolutions: { type: "object" },
                  companySizeSectionFeaturedSolution: { type: "object" },
                  industrySectionIntro: { type: "object" },
                  industrySectionSolutions: { type: "object" },
                  useCaseSectionIntro: { type: "object" },
                  useCaseSectionSolutions: { type: "object" },
                  ctaBanner: { type: "object" },
                },
                required: %w[
                  title
                  hero
                  heroBackgroundImage
                  companySizeSectionIntro
                  companySizeSectionSolutions
                  companySizeSectionFeaturedSolution
                  industrySectionIntro
                  industrySectionSolutions
                  useCaseSectionIntro
                  useCaseSectionSolutions
                  ctaBanner
                ],
              }
            end
          end
        end
      end
    end
  end
end
