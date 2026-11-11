# typed: true
# frozen_string_literal: true

class CodeScanning::SuggestedFixDependencyMetadataComponent < ApplicationComponent
  attr_reader :dependency_metadata

  def initialize(dependency_metadata:)
    @dependency_metadata = dependency_metadata
  end

  def render?
    dependency_metadata.any?
  end

  def advisories?(dependency)
    dependency.advisories.any?
  end

  def advisory_severity_label(advisory)
    case advisory.severity
    when :ADVISORY_SEVERITY_LOW
      "Low severity"
    when :ADVISORY_SEVERITY_MEDIUM
      "Medium severity"
    when :ADVISORY_SEVERITY_HIGH
      "High severity"
    when :ADVISORY_SEVERITY_CRITICAL
      "Critical severity"
    when :ADVISORY_SEVERITY_UNKNOWN
      "Unknown severity"
    end
  end

  def advisory_severity_font_color(advisory)
    case advisory.severity
    when :ADVISORY_SEVERITY_LOW
      :attention
    when :ADVISORY_SEVERITY_MEDIUM
      :severe
    when :ADVISORY_SEVERITY_HIGH
      :danger
    when :ADVISORY_SEVERITY_CRITICAL
      :danger
    when :ADVISORY_SEVERITY_UNKNOWN
      :default
    end
  end
end
