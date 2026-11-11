# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchQueryParsingFatalError < Platform::Models::CodeSearchError
  attr_reader :ranges

  def initialize(message: "", ranges: [])
    super(message:)

    @ranges = ranges || []
  end

  def platform_type_name
    "CodeSearchQueryParsingFatalError"
  end
end
