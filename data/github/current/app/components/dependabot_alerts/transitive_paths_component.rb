# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TransitivePathsComponent < ApplicationComponent

    def initialize(alert:, transitive_results:)
      @alert = alert
      @transitive_results = transitive_results
    end

    attr_reader :alert, :transitive_results

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
      return false unless DependencyGraph::VulnerableDependencyProvider.relationship_information_available?
      return false unless alert.open?
      return false if has_no_data?

      true
    end

    def has_no_data?
      return true if transitive_results.nil?

      transitive_results[:paths]&.empty? && transitive_results[:error]&.empty?
    end

    def paths
      transitive_results[:paths]
    end

    def error
      transitive_results[:error]
    end

    def format_requirements(requirements)
      requirements
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end
  end
end
