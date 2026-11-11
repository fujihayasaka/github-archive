# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchFacet
  attr_reader :query

  def initialize(query:)
    @query = query.to_s
  end
end
