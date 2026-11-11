# typed: true
# frozen_string_literal: true

module Hookshot
  class HookshotError < StandardError
    def failbot_context
      {
        "app" => "github-event-dispatch",
      }
    end
  end
end
