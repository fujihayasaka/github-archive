# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchInaccessibleRepoError < Platform::Models::CodeSearchError
  attr_reader :name_with_owner, :ranges

  def initialize(message: "", name_with_owner: "", ranges: [])
    super(message:)

    @name_with_owner = name_with_owner.to_s
    @ranges          = ranges || []
  end

  def platform_type_name
    "CodeSearchInaccessibleRepoError"
  end
end
