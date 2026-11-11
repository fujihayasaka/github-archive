# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchQueryParsingWarningError < Platform::Models::CodeSearchError
  attr_reader :ranges, :suggestion

  def initialize(message: "", suggestion:, ranges: [])
    super(message:)

    @ranges     = ranges || []
    @suggestion = suggestion.to_s
  end

  def platform_type_name
    "CodeSearchQueryParsingWarningError"
  end
end
