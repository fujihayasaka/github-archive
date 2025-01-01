# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module MentionSuggestable
      include Platform::Interfaces::Base
      description "An object that supports user or team mention suggestions."
      mobile_only true

      field :mentionable_items, resolver: Resolvers::MentionableItems, description: "A list of mentionable items that can be mentioned in the context of this object.",
        connection: true, null: true
    end
  end
end
