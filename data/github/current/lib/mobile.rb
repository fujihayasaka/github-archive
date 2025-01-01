# typed: true
# frozen_string_literal: true

module Mobile
  autoload :Apple, "mobile/apple"
  autoload :Google, "mobile/google"
  autoload :ClientPublicApiFeatureFlags, "mobile/client_public_api_feature_flags"
end
