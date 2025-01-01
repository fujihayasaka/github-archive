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
      advisory&.cvss_v4 ? advisory&.cvss_v4 : advisory&.cvss_v3
    end

    def cvss_placeholder
      "CVSS:3.1/AV:_/AC:_/PR:_/UI:_/S:_/C:_/I:_/A:_"
    end

    def field_name_prefix
      form.object_name
    end

    def score
      if current_cvss&.starts_with?("CVSS:4.0")
        advisory.cvss_v4_score.round(1)
      elsif current_cvss&.starts_with?("CVSS:3.0") || current_cvss&.starts_with?("CVSS:3.1")
        advisory.cvss_v3_score.round(1)
      else
        nil
      end
    end

    def severity
      current_cvss ? advisory.severity : nil
    end

    def severity_selected
      if advisory.cvss_v4.blank? && advisory.cvss_v3.blank?
        advisory.severity
      elsif !advisory.cvss_v4.blank?
        "cvss_v4"
      elsif !advisory.cvss_v3.blank?
        "cvss_v3"
      end
    end
  end
end
