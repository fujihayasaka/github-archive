# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Core
        module Schemas
          module IndexTemplate
            sig { returns(T::Hash[T.untyped, T.untyped]) }
            def self.build
              {
                "$schema": "http://json-schema.org/draft-06/schema#",
                title: "templateIndex",
                type: "object",
                properties: {
                  sys: {
                    type: "object",
                    properties: {
                      contentType: {
                        type: "object",
                        properties: {
                          sys: {
                            type: "object",
                            properties: {
                              id: { const: "templateIndex" },
                            },
                            required: %w[id],
                          },
                        },
                        required: %w[sys],
                      },
                    },
                    required: %w[contentType],
                  },
                  fields: {
                    type: "object",
                    properties: {
                      hero: { type: "object" },
                      cards: { type: "array" },
                      filters: { type: "array" },
                    },
                    required: %w[hero cards filters]
                  },
                },
                required: %w[sys fields],
              }
            end
          end
        end
      end
    end
  end
end
