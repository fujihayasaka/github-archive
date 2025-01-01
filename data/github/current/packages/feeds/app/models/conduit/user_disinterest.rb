# typed: true
# frozen_string_literal: true
module Conduit
  class UserDisinterest
    REASON_DESCRIPTIONS = {
      RESOURCE: "User is not interested in this resource.",
      EVENT_TYPE: "User is not interested in this type of event.",
      EVENT_TYPE_RESOURCE: "User is not interested in this type of event from this resource.",
      DISMISSED: "User has dismissed this event."
    }.freeze

    REASONS = REASON_DESCRIPTIONS.keys.freeze
  end
end
