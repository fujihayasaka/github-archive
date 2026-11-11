# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchIncompleteResultsError < Platform::Models::CodeSearchError
  def platform_type_name
    "CodeSearchIncompleteResultsError"
  end
end
