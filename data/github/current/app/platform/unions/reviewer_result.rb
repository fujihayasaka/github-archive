# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ReviewerResult < Platform::Unions::Base
      docs_category :pulls
      description "The results of a reviewer search."
      possible_types(
        Objects::User,
        Objects::Team,
      )
    end
  end
end
