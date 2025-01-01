# typed: true
# frozen_string_literal: true

module Advisories
  class SeverityCalculatorComponent < ApplicationComponent
    METRICS = [
      {
        name: "Attack vector",
        code: "AV",
        choices: [
          {
            name: "Network",
            code: "N",
          },
          {
            name: "Adjacent",
            code: "A",
          },
          {
            name: "Local",
            code: "L",
          },
          {
            name: "Physical",
            code: "P",
          },
        ],
      },
      {
        name: "Attack complexity",
        code: "AC",
        choices: [
          {
            name: "Low",
            code: "L",
          },
          {
            name: "High",
            code: "H",
          },
        ],
      },
      {
        name: "Privileges required",
        code: "PR",
        choices: [
          {
            name: "None",
            code: "N",
          },
          {
            name: "Low",
            code: "L",
          },
          {
            name: "High",
            code: "H",
          },
        ],
      },
      {
        name: "User interaction",
        code: "UI",
        choices: [
          {
            name: "None",
            code: "N",
          },
          {
            name: "Required",
            code: "R",
          },
        ],
      },
      {
        name: "Scope",
        code: "S",
        choices: [
          {
            name: "Unchanged",
            code: "U",
          },
          {
            name: "Changed",
            code: "C",
          },
        ],
      },
      {
        name: "Confidentiality",
        code: "C",
        choices: [
          {
            name: "None",
            code: "N",
          },
          {
            name: "Low",
            code: "L",
          },
          {
            name: "High",
            code: "H",
          },
        ],
      },
      {
        name: "Integrity",
        code: "I",
        choices: [
          {
            name: "None",
            code: "N",
          },
          {
            name: "Low",
            code: "L",
          },
          {
            name: "High",
            code: "H",
          },
        ],
      },
      {
        name: "Availability",
        code: "A",
        choices: [
          {
            name: "None",
            code: "N",
          },
          {
            name: "Low",
            code: "L",
          },
          {
            name: "High",
            code: "H",
          },
        ],
      },
    ].freeze

    attr_reader :expanded

    def initialize(expanded: false, hidden: false, data: {})
      @expanded = expanded
      @hidden = hidden
      @data = data
    end

    def data_attributes
      safe_data_attributes(@data)
    end

    def score_documentation_url
      "https://www.first.org/cvss/v3.1/user-guide"
    end
  end
end
