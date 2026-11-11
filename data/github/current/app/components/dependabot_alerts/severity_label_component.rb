# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class SeverityLabelComponent < ApplicationComponent
    SEVERITY_SCHEME = {
      "critical" => :danger,
      "high" =>  :orange,
      "moderate" => :warning,
      "low" => :primary
    }

    def initialize(severity:, capitalize: true, verbose: true, **kwargs)
      @severity = severity&.downcase
      @capitalize = capitalize
      @verbose = verbose
      @kwargs = kwargs

      unless kwargs.include?(:tag)
        @kwargs[:tag] = if kwargs.include?(:href)
          :a
        else
          :span
        end
      end
    end

    def render?
      severity.present?
    end

    private

    attr_reader :severity

    def scheme
      SEVERITY_SCHEME[severity] || :default
    end

    def capitalize?
      @capitalize
    end

    def verbose?
      @verbose
    end

    def text
      "#{capitalize? ? severity.capitalize : severity}" + (verbose? ? " severity" : "")
    end
  end
end
