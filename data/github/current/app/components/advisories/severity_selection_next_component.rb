# typed: true
# frozen_string_literal: true

module Advisories
  class SeveritySelectionNextComponent < ApplicationComponent
    attr_reader :advisory, :repository, :classes, :form, :required

    def initialize(advisory:, repository: nil, classes: "", form:, required:)
      @advisory = advisory
      @repository = repository
      @classes = classes
      @form = form
      @required = required
    end

    def current_cvss
      advisory&.cvss_v4
    end

    def cvss_placeholder
      "CVSS:4.0/AV:_/AC:_/AT:_/PR:_/UI:_/VC:_/VI:_/VA:_/SC:_/SI:_/SA:_"
    end

    def field_name_prefix
      form.object_name
    end

    def score
      current_cvss ? advisory.cvss_v4_score.round(1) : nil
    end

    def severity
      current_cvss ? advisory.severity : nil
    end

    def severity_selected
      advisory.cvss_v4.blank? ? advisory.severity : "cvss"
    end
  end
end
