# frozen_string_literal: true

module HydroHandlers
  # The package manager we ingest from hydro message has a different
  # mapping than what this system expects. So we need to translate it
  def self.package_manager_for(ecosystem:)
    GitHub::SecurityVulnerability::PACKAGE_MANAGER_MATRIX.fetch(ecosystem&.to_sym, "unknown")
  end
end
