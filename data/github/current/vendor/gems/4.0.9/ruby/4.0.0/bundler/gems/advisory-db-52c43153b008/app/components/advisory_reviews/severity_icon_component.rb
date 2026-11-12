# frozen_string_literal: true

module AdvisoryReviews
  class SeverityIconComponent < ApplicationComponent
    include HasSeverities

    attr_reader :severity, :octicon_args

    def initialize(severity:, **octicon_args)
      @severity = severity
      @octicon_args = octicon_args
    end

    def call
      render IconComponent.new(
        icon: :shield,
        color: severity_scheme(severity),
        title: severity_label(severity),
        test_selector: "advisory-severity-icon",
        **octicon_args,
      )
    end
  end
end
