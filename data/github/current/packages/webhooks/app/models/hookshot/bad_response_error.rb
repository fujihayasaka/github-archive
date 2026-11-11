# typed: true
# frozen_string_literal: true

module Hookshot
  class BadResponseError < HookshotError

    def initialize(status, body = nil)
      msg = "Expected 200 response but got #{status}"
      msg += " <Body: #{body}>" if body.present?
      super msg
    end

  end
end
