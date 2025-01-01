# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SearchResultComponent < ApplicationComponent
    delegate :package_name,
        :manifest_path,
        :scanned_by,
        :snapshot_detector_name,
        :license,
      to: :@search_result

    attr_reader :alerts, :package_repository, :repository

    def initialize(search_result:, alerts:, package_repository: nil, repository:)
      @search_result = search_result
      @package_repository = package_repository
      @repository = repository
      @alerts = alerts
    end

    def package_manager
      case @search_result.package_manager
      when :PACKAGE_MANAGER_UNKNOWN
        "unknown"
      when :PACKAGE_MANAGER_RUBYGEMS
        "RubyGems"
      when :PACKAGE_MANAGER_NPM
        "npm"
      when :PACKAGE_MANAGER_PIP
        "pip"
      when :PACKAGE_MANAGER_MAVEN
        "Maven"
      when :PACKAGE_MANAGER_NUGET
        "NuGet"
      when :PACKAGE_MANAGER_COMPOSER
        "Composer"
      when :PACKAGE_MANAGER_GOMOD
        "Go modules"
      when :PACKAGE_MANAGER_RUST
        "Cargo"
      when :PACKAGE_MANAGER_ACTIONS
        "GitHub Actions"
      when :PACKAGE_MANAGER_PUB
        "pub"
      when :PACKAGE_MANAGER_SWIFT
        "Swift"
      end
    end

    def requirements
      @search_result.requirements
        .sub(/\A=\s+/, "")
        .gsub(/,(?=[^\s])/, ", ")
    end

    def scanned_at
      @search_result.scanned_at.to_time.strftime("%b %d, %Y")
    end

    def render_relationship_label
      case @search_result.relationship
      when :RELATIONSHIP_UNKNOWN
        # If the relationship is unknown, don't render any label
        nil
      when :RELATIONSHIP_DIRECT
        render(Primer::Beta::Label.new(ml: 2, scheme: :primary)) { "Direct" }
      when :RELATIONSHIP_INDIRECT
        render(Primer::Beta::Label.new(ml: 2, scheme: :default)) { "Transitive" }
      when :RELATIONSHIP_INCONCLUSIVE
        render(Primer::Beta::Label.new(ml: 2, scheme: :secondary)) { "Inconclusive" }
      end
    end
  end
end
