# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class FollowOrderField < Platform::Enums::Base
      description "Properties by which follow connections can be ordered."

      visibility :under_development

      value "FOLLOWED_AT", "Order users by when they began following the user.",
        value: "followed_at"
    end
  end
end
