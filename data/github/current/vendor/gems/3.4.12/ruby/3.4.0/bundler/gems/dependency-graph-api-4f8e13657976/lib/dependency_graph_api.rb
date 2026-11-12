require "ghconfig"

module DependencyGraphAPI
  extend GhConfig

  def self.snapshots_enabled?
    !DependencyGraphAPI.enterprise? || (ENV.fetch("SNAPSHOTS_ENABLED_ON_ENTERPRISE", "0") == "1")
  end
end
