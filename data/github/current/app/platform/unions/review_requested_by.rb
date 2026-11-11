# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ReviewRequestedBy < Platform::Unions::Base
      description "Types that can request reviews."

      possible_types(
        Objects::User,
        Objects::Bot,
      )
    end
  end
end
