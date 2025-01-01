# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class WebcamUploadComponent < ApplicationComponent
        PARTIAL_NAME = T.let("webcam-upload".freeze, String)

        sig { params(allow_file_upload: T::Boolean, form_field_id: String).void }
        def initialize(allow_file_upload:, form_field_id:)
          @allow_file_upload = allow_file_upload
          @form_field_id = form_field_id
        end

        sig { returns(T.nilable(String)) }
        def call
          safe_join([
            content_tag(:div, data: { test_selector: "webcam-upload" }) do
              render_react_partial(
                name: PARTIAL_NAME,
                props: {
                  allowFileUpload: !!@allow_file_upload,
                  formFieldId: @form_field_id,
                },
              )
            end,
          ])
        end

        private

        sig { returns(T::Boolean) }
        def render?
          @form_field_id.present?
        end
      end
    end
  end
end
