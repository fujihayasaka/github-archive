# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class MentionableItem < Platform::Unions::Base
      description "An item that is mentionable on an issue/pull request"

      mobile_only true

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::Bot
      )
    end
  end
end
