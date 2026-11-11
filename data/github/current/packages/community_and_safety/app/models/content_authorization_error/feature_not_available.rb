# typed: true
# frozen_string_literal: true

# Error indicating that the feature is not available for this content
class ContentAuthorizationError::FeatureNotAvailable < ContentAuthorizationError
  def message
    "You can't perform that action at this time."
  end
end
