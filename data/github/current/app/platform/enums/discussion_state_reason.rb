# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionStateReason < Platform::Enums::Base
      description "The possible state reasons of a discussion."

      Discussion::StateReasonable::StateReason.values.each do |reason|
        value reason.serialize.upcase, reason.description, value: reason.serialize
      end
    end
  end
end
