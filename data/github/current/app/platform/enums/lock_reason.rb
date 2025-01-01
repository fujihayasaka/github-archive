# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class LockReason < Platform::Enums::Base
      description "The possible reasons that an issue or pull request was locked."

      Issue::LOCK_REASONS.each do |reason|
        value self.convert_string_to_enum_value(reason), "The issue or pull request was locked because the conversation was #{reason}.", value: reason
      end
    end
  end
end
