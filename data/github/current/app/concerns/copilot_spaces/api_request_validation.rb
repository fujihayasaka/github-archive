# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module ApiRequestValidation
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Api::App }

    CANONICAL_SPACE_NUMBER = T.let(/\A[1-9]\d*\z/, Regexp)
    JSON_MEDIA_TYPE = "application/json"

    sig { params(space_number: T.untyped).returns(Integer) }
    def parse_space_number!(space_number)
      space_number_string = space_number.to_s
      deliver_error!(404) unless CANONICAL_SPACE_NUMBER.match?(space_number_string)
      space_number_string.to_i
    end

    sig { void }
    def ensure_json_request_body!
      media_type = request.media_type
      return if media_type.blank? || media_type == JSON_MEDIA_TYPE || media_type.end_with?("+json")

      deliver_error!(415, message: "Unsupported Media Type")
    end
  end
end
