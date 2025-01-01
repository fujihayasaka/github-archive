# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchInconsistentResultsError < Platform::Models::CodeSearchError
  def platform_type_name
    "CodeSearchInconsistentResultsError"
  end
end
