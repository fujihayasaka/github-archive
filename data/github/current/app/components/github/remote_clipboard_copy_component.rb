# typed: true
# frozen_string_literal: true

module GitHub
  class RemoteClipboardCopyComponent < ApplicationComponent
    renders_one :idle, -> { StateComponent.new(name: :idle) }
    renders_one :fetching, -> { StateComponent.new(name: :fetching) }
    renders_one :success, -> { StateComponent.new(name: :success) }
    renders_one :error, -> { StateComponent.new(name: :error) }

    def initialize(src:, classes: nil, styles: nil)
      @src = src
      @classes = classes
      @styles = styles
    end

    # Don't render `<remote-clipboard-copy>` for Firefox. Currently, Firefox
    # only supports `ClipboardItem` via a `about:config` setting that is disabled
    # by default. Even if enabled, Firefox doesn't handle content being provided as
    # a promise and will just add '[object Promise]' to the clipboard.
    def render?
      browser = helpers.parsed_useragent
      return false if browser.device.mobile?

      browser.edge? || browser.chrome? || safari_13_1_or_greater?(browser)
    end

    private

    def safari_13_1_or_greater?(browser)
      return false unless browser.safari?

      browser.version.to_i >= 14 || browser.full_version.starts_with?("13.1")
    end

    class StateComponent < ApplicationComponent
      IDLE = :idle

      attr_reader :name, :hidden

      def initialize(name:)
        @name = name
        @hidden = name != IDLE
      end

      def call
        content_tag :span, content, "data-target": "remote-clipboard-copy.#{name}", hidden: hidden
      end
    end
  end
end
