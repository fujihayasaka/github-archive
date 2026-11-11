# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PinnableItem < Platform::Unions::Base
      description "Types that can be pinned to a profile page."

      possible_types(Objects::Gist, Objects::Repository)
    end
  end
end
