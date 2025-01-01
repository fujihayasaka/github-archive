# typed: true
# frozen_string_literal: true

module Importable
  def importing?
    true
  end

  # Default values for development can be found in lib/github/config/environments/development.rb
  def creation_rate_limit_configuration
    GitHub.octoshift_importable_creation_rate_limit_configuration
  end

  def apply_dynamic_rate_limit_configuration?
    return @apply_dynamic_rate_limit_configuration if defined?(@apply_dynamic_rate_limit_configuration)
    @apply_dynamic_rate_limit_configuration = \
      GitHub.flipper[:octoshift_importable_creation_rate_limits].enabled?
  end
end
