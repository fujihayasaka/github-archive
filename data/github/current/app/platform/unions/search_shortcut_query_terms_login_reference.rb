# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class SearchShortcutQueryTermsLoginReference < Platform::Unions::Base
      description "Types that can be referenced by login in a search shortcut query term."

      possible_types(
        Objects::Bot,
        Objects::Mannequin,
        Objects::Organization,
        Objects::User,
      )
    end
  end
end
