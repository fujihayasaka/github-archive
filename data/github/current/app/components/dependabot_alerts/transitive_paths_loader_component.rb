# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TransitivePathsLoaderComponent < ApplicationComponent
    def initialize(alert:)
      @alert = alert
    end

    attr_reader :alert

    def render?
      # This mostly gates on enterprise, where transitive information is not available
      return false unless DependencyGraph::VulnerabilityScanning.relationship_information_available?
      # Transitive paths will not exist if the relationship is unknown. DG-API will always be unknown, but
      # both DS-API and DGP backed alerts can have other dependency relationships
      return false if alert.dependency_relationship == "unknown"
      # If the alert's relationship is inconclusive then it was created using DGP data but unable to be categorized.
      return false if alert.dependency_relationship == "inconclusive"
      # We should request transitive paths for open alerts, for any other state DGP cannot be expected to
      # retain information as the dependency or manifest may have been removed entirely.
      return false unless alert.open?

      true
    end

    def dependency_path
      UrlHelpers.repository_alert_dependency_path(
        user_id: alert.repository.owner.display_login,
        repository: alert.repository.name,
        number: alert.number,
      )
    end
  end
end
