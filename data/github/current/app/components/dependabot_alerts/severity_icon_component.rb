# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class SeverityIconComponent < ApplicationComponent
    SEVERITY_SCHEME = {
      "critical" => { color: :danger },
      "high" =>  { color: :severe },
      "moderate" => { color: :attention },
      "low" => { color: :default }
    }

    def initialize(severity:, withdrawn: false, **args)
      @severity = severity&.downcase
      @withdrawn = withdrawn
      @args = args
    end

    def call
      primer_octicon(icon, **scheme, **@args)
    end

    def render?
      @severity.present?
    end

    private

    def scheme
      SEVERITY_SCHEME[@severity]
    end

    def icon
      if @withdrawn
        "shield-x"
      else
        "shield"
      end
    end
  end
end
