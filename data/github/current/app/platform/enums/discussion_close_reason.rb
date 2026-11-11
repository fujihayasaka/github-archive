# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionCloseReason < Platform::Enums::Base
      description "The possible reasons for closing a discussion."

      Discussion::StateReasonable::CloseReason.values.each do |reason|
        value reason.serialize.upcase, reason.description, value: reason.serialize
      end
    end
  end
end
