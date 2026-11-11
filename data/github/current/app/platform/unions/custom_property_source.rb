# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CustomPropertySource < Platform::Unions::Base
      docs_category :repos
      description "Sources which can have custom properties defined."

      possible_types(
        Objects::Organization,
        Objects::Enterprise,
      )
    end
  end
end
