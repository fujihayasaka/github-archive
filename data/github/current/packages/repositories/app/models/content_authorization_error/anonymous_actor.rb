# typed: true
# frozen_string_literal: true

# Error indicating that this operation cannot be performed by an anonymous
# actor.
class ContentAuthorizationError::AnonymousActor < ContentAuthorizationError
  def message
    "You must be logged in to do that."
  end

  def http_error_code
    401
  end

  def documentation_url
    "/rest/guides/getting-started-with-the-rest-api#authentication"
  end
end
