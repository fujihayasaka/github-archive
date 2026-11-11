# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ReviewRequestedBy < Platform::Unions::Base
      docs_category :pulls
      description "Types that can request reviews."

      possible_types(
        Objects::User,
        Objects::Bot,
      )
    end
  end
end
