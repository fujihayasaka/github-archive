# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchPathFacet < Platform::Models::CodeSearchFacet
  attr_reader :path

  def initialize(path:, query:)
    super(query:)

    @path = path.to_s
  end

  def platform_type_name
    "CodeSearchPathFacet"
  end
end
