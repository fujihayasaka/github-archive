# typed: true
# frozen_string_literal: true

module Repository::RateLimitDependency
  extend T::Helpers

  requires_ancestor { Repository }
  CUSTOM_CREATE_RATE_LIMIT_NAME = "_repo"

  # Overrides of RateLimitedCreation mixin
  def user_for_rate_limited_creation
    created_by
  end

  def custom_create_rate_limit_name
    CUSTOM_CREATE_RATE_LIMIT_NAME
  end
end
