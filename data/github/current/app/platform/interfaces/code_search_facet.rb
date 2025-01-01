# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module CodeSearchFacet
      include Platform::Interfaces::Base

      description "A way to further refine a search query."

      mobile_only true

      field :query, String, description: "Snippet that can be injected in the query", null: false
    end
  end
end
