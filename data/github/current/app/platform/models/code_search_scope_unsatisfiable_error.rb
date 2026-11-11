# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchScopeUnsatisfiableError < Platform::Models::CodeSearchError
  def platform_type_name
    "CodeSearchScopeUnsatisfiableError"
  end
end
