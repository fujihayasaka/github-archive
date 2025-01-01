# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Settings::Education
  class WebcamUploadComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    test "it renders the component" do
      render_inline(
        WebcamUploadComponent.new(form_field_id: "webcam", allow_file_upload: true),
        allowed_queries: 1,
      )

      assert_test_selector("webcam-upload")
    end

    test "it does not render the component when form_field_id is a blank string" do
      render_inline(
        WebcamUploadComponent.new(form_field_id: "", allow_file_upload: true),
        allowed_queries: 1,
      )

      refute_test_selector("webcam-upload")
    end
  end
end
