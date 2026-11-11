# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IpAllowListOwner < Platform::Unions::Base
      description "Types that can own an IP allow list."

      possible_types(
        Objects::Enterprise,
        Objects::Organization,
        Objects::App,
      )
    end
  end
end
