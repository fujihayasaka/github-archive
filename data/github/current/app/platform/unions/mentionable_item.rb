# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class MentionableItem < Platform::Unions::Base
      description "An item that is mentionable on an issue/pull request"

      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::Bot
      )
    end
  end
end
