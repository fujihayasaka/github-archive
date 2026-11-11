# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class RequestedReviewer < Platform::Unions::Base
      description "Types that can be requested reviewers."

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::Mannequin,
        Objects::Bot,
      )
    end
  end
end
