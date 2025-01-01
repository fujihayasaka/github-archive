# frozen_string_literal: true

module AdvisoryReviews
  class SourceIconComponent < ApplicationComponent
    attr_reader :source, :with_link

    def initialize(source:, with_link: true)
      @source = source
      @with_link = with_link
    end

    def source_data
      AdvisoryReviews::SOURCES[@source]
    end

    def label
      # The fallback color is Primer's default text color for a "secondary" label.
      # See: https://primer.style/css/components/labels
      data = source_data.presence || { label: "Deprecated: #{source}", icon: "???", color: "586069" }

      render Primer::Beta::Label.new(
        title: data[:label],
        classes: "text-mono",
        style: "color: ##{data[:color]}; border-color: ##{data[:color]}",
        test_selector: "advisory-source-icon",
      ) do
        data[:icon]
      end
    end
  end
end
