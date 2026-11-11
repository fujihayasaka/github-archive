# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class FeedItemRelatedBy < Platform::Enums::Base
      description "How the feed item's related items are related"

      value "NONE", "There are no related items", value: :RELATED_BY_NONE
      value "ACTOR", "Items are related by actor", value: :RELATED_BY_ACTOR
      value "SUBJECT", "Items are related by subject", value: :RELATED_BY_SUBJECT
    end
  end
end
