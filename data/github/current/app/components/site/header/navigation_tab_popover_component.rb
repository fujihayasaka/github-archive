# typed: strict
# frozen_string_literal: true

module Site
  module Header
    class NavigationTabPopoverComponent < Primer::Component
      sig { params(heading: String, body_text: String, notice: String, dismiss_notice_href: String, cta: T.nilable({ text: String, href: String })).void }
      def initialize(heading:, body_text:, notice:, dismiss_notice_href:, cta: nil)
        @heading = heading
        @body_text = body_text
        @notice = notice
        @dismiss_notice_href = dismiss_notice_href
        @cta = cta
      end
    end
  end
end
