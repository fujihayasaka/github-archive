# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module LandingPages
        module Schemas
          module ContactSalesTemplate
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-04/schema#",
                title: "templateContactSalesForm",
                type: "object",
                properties: {
                  body: { type: "object" },
                  headline: { type: "string" },
                  label: { type: "string" },
                  highlight: { type: "object" },
                  branding: {
                    type: "string",
                    in: %w[Platform AI Security],
                  },
                  form: { type: "object" },
                  formRequirementMessage: { type: "object" },
                },
                required: %w[headline]
              }
            end
          end
        end
      end
    end
  end
end
