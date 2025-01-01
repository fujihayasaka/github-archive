# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class BridgeMailerTest < GitHub::TestCase
    CSS_PATH = "test/integration/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler/primer-test.scss"

    setup do
      MailerBundleHelper.stubs(:primer_email_stylesheet_uris).returns(["file:/#{Rails.root.join(CSS_PATH)}"])
    end

    context "#build_mail" do
      test "renders each part" do
        message = stub(
          comment: stub_everything,
          parts: [
            ["text/plain", "This is a test"],
            ["text/html", "<p>This is a test</p>"],
          ],
          primer_html_template_enabled?: false,
        )
        subject = "Notifyd: bridge"

        mail = BridgeMailer.with(subject: subject, message: message).build_mail

        assert_equal mail.subject, subject
        assert_equal mail.text_part.body.to_s, "This is a test"
        assert_equal mail.html_part.body.to_s, "<p>This is a test</p>"
      end

      test "renders html parts with primer layouts" do
        BridgeMailer.append_view_path Rails.root.join("test", "mailers")
        message = stub(
          comment: stub_everything,
          parts: [
            ["text/plain", "This is a test"],
            ["text/html", :test_template],
          ],
          primer_html_template_enabled?: true,
          primer_layout: :primer_layout,
          heading: "render header using primer layout",
          footer_html: "footer",
        )
        subject = "Notifyd: bridge"

        mail = BridgeMailer.with(subject: subject, message: message).build_mail

        html_content = Nokogiri::HTML::Document.parse(mail.html_part.body.to_s)
        assert_match "multipart/alternative", mail.content_type
        assert_select html_content, "h2", text: "render header using primer layout"
        assert_select html_content, "p", text: "rendered html"
        assert_select html_content, "style", count: 0

        # NOTE: the mailer generated is lazy and only generates the html_part when it's
        #   accessed, that's why the request check has to be done after calling mail.html_part
        assert_primer_not_css_requested
      end
    end
  end
end
