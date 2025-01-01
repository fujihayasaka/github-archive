# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class BridgeMailRendererTest < GitHub::TestCase
    class StubMessage
      def initialize(delivery, settings, options)
        @delivery = delivery
        @settings = settings
      end

      def comment
        Object.new
      end

      def parts
        [
          ["text/plain", "This is a test"],
          ["text/html", :test_template],
        ]
      end

      def primer_html_template_enabled?
        true
      end

      def primer_layout
        :primer_layout
      end

      def heading
        "render header using primer layout"
      end

      def footer_html
        "footer"
      end
    end

    setup do
      BridgeMailer.append_view_path Rails.root.join("test", "mailers")
      @user = create(:user)
      @subject = "Notifyd: bridge"
    end

    context "#parts" do
      test "renders text part" do
        renderer = BridgeMailRenderer.new(
          subject: @subject,
          user: @user,
          comment: Object.new,
          message_class: StubMessage
        )

        assert_equal renderer.parts.size, 2

        text = renderer.parts[0]
        assert_equal text.headers["Content-Type"], "text/plain; charset=UTF-8"
        assert_equal text.content, "This is a test"
      end

      test "renders html part" do
        renderer = BridgeMailRenderer.new(
          subject: @subject,
          user: @user,
          comment: Object.new,
          message_class: StubMessage
        )

        assert_equal renderer.parts.size, 2

        html = renderer.parts[1]
        assert_equal html.headers["Content-Type"], "text/html; charset=UTF-8"

        html_content = Nokogiri::HTML::Document.parse(html.content)
        assert_select html_content, "h2", text: "render header using primer layout"
        assert_select html_content, "p", text: "rendered html"
        assert_select html_content, "style", count: 0
      end
    end
  end
end
