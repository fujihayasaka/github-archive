# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRecommendationReason < Platform::Enums::Base
      description "The reason a particular repository was recommended to a user."
      required_capabilities [:mobile_only_schema_mask]

      value "TRENDING", "The repository is currently trending on GitHub.", value: "trending"
      value "TOPICS", "The repository is part of a topic that the user is interested in.", value: "topics"
      value "STARRED", "The repository is like other repositories the user has starred.",
        value: "starred"
      value "FOLLOWED", "Someone the user follows starred the repository.", value: "followed"
      value "POPULAR", "The repository is popular on GitHub.", value: "popular"
      value "VIEWED", "The repository is similar to other repositories the user has viewed.",
        value: "viewed"
      value "CONTRIBUTED", "The repository is similar to repositories the user has contributed to.",
        value: "contributed"
      value "OTHER", "The repository was recommended for some other reason.", value: "other"
    end
  end
end
