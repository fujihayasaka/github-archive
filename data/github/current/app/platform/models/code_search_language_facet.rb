# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchLanguageFacet < Platform::Models::CodeSearchFacet
  attr_reader :color, :name

  def initialize(color:, name:, query:)
    super(query:)

    @color = color.to_s
    @name  = name.to_s
  end

  def platform_type_name
    "CodeSearchLanguageFacet"
  end
end
