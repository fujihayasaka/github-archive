# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewPubSubTopic < Platform::Enums::Base
      docs_category :pulls
      description "The possible PubSub channels for a pull request."
      visibility :internal

      value "UPDATED", "The channel ID for observing pull request review updates.", value: "updated"
    end
  end
end
