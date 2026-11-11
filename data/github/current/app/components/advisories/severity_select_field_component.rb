# typed: true
# frozen_string_literal: true

module Advisories
  class SeveritySelectFieldComponent < ApplicationComponent
    attr_reader :asterisk_shown, :form, :required, :selected

    def initialize(form:, asterisk_shown: false, selected: nil, required: true)
      @asterisk_shown = asterisk_shown
      @form = form
      @required = required
      @selected = selected
    end

    def choices
      RepositoryAdvisory.severities.keys.map { |s| [s.to_s.humanize, s] }.concat([["Assess severity using CVSS", "cvss"]])
    end
  end
end
