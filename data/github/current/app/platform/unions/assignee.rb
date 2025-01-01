# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Assignee < Platform::Unions::Base
      description "Types that can be assigned to issues."

      possible_types(
        Objects::Bot,
        Objects::Mannequin,
        Objects::Organization,
        Objects::User,
      )
    end
  end
end
