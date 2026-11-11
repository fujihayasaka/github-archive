# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ReviewDismissalAllowanceActor < Platform::Unions::Base
      docs_category :branches
      description "Types that can be an actor."

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::App,
      )
    end
  end
end
