# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchRepoFacet < Platform::Models::CodeSearchFacet
  attr_reader :name_with_owner

  def initialize(query:, name_with_owner: "")
    super(query:)

    @name_with_owner = name_with_owner.to_s
  end

  def platform_type_name
    "CodeSearchRepoFacet"
  end
end
