# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class RequestedReviewer < Platform::Unions::Base
      docs_category :pulls
      description "Types that can be requested reviewers."

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::EnterpriseTeam,
        Objects::Mannequin,
        Objects::Bot,
      )
    end
  end
end
