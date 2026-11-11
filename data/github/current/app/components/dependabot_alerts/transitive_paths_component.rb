# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TransitivePathsComponent < ApplicationComponent

    def initialize(alert:, transitive_paths: [])
      @alert = alert
      @transitive_paths = transitive_paths
    end

    attr_reader :alert, :transitive_paths

    delegate \
      :repository,
      :package_name,
      :vulnerable_requirements,
      :dependency_relationship,
      to: :alert

    def requirements
      format_requirements(vulnerable_requirements)
    end

    def render?
      return false unless DependencyGraph::VulnerabilityScanning.relationship_information_available?
      return false unless alert.open?
      return false if transitive_paths&.empty?

      true
    end

    def format_requirements(requirements)
      requirements
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end
  end
end
