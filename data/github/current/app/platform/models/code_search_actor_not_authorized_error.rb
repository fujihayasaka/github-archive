# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchActorNotAuthorizedError < Platform::Models::CodeSearchError
  def platform_type_name
    "CodeSearchActorNotAuthorizedError"
  end
end
