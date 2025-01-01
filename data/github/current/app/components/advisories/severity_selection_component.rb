# typed: true
# frozen_string_literal: true

module Advisories
  class SeveritySelectionComponent < ApplicationComponent
    attr_reader :advisory, :repository, :classes, :form, :required

    def initialize(advisory:, repository: nil, classes: "", form:, required:)
      @advisory = advisory
      @repository = repository
      @classes = classes
      @form = form
      @required = required
    end

    def current_cvss
      advisory&.cvss_v3
    end

    def cvss_placeholder
      Advisories::SeverityCalculatorComponent::METRICS.reduce("CVSS:3.1") do |placeholder, metric|
        placeholder + "/#{metric[:code]}:_"
      end
    end

    def field_name_prefix
      form.object_name
    end

    def score
      current_cvss ? advisory.cvss_v3_score.round(1) : nil
    end

    def severity
      current_cvss ? advisory.severity : nil
    end

    def severity_selected
      advisory.cvss_v3.blank? ? advisory.severity : "cvss"
    end
  end
end
