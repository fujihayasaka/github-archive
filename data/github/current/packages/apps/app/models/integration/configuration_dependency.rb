# typed: true
# frozen_string_literal: true

module Integration::ConfigurationDependency
  extend ActiveSupport::Concern

  include Configurable
  include Configurable::IpAllowlistEnabled

  # Internal: Get the configuration owner.
  #
  # Values for a Business can be cascaded from (or overridden by) the global
  # GitHub object.
  def configuration_owner
    GitHub
  end
end
