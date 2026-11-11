# typed: true
# frozen_string_literal: true

module Api::Serializer
  class InvalidTimestampError < TypeError
    def failbot_context
      { app: "github-octolytics" }
    end
  end
end
