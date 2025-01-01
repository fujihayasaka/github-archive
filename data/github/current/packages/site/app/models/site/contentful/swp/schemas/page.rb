# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Schemas
        module Page
          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def self.build
            {
              "$schema": "http://json-schema.org/draft-04/schema#",
              "type": "object",
              "properties": {
                "title": { "type": "string" },
                "path": { "type": "string" },
                "template": { "type": "object" },
                "settings": { "type": "object" },
                "seo": { "type": "object" },
              },
              "required": %w[path template],
            }
          end
        end
      end
    end
  end
end
