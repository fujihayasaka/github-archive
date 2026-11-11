# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CodeSearchFacets < Platform::Unions::Base
      docs_category :search
      description "All code search query refinements (facets)"

      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::CodeSearchInvalidFacet,
        Objects::CodeSearchLanguageFacet,
        Objects::CodeSearchPathFacet,
        Objects::CodeSearchRepoFacet,
      )
    end
  end
end
