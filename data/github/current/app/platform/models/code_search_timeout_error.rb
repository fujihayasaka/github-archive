# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchTimeoutError < Platform::Models::CodeSearchError
  def platform_type_name
    "CodeSearchTimeoutError"
  end
end
