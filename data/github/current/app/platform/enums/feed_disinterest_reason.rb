# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class FeedDisinterestReason < Platform::Enums::Base
      description "The possible reasons that a user expressed disinterest in a Feed event."

      ::Conduit::UserDisinterest::REASON_DESCRIPTIONS.each do |key, reason|
        value self.convert_string_to_enum_value(key.to_s), reason, value: key.to_s
      end
    end
  end
end
