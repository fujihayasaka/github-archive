# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class AppOwner < Platform::Unions::Base
      description "Types that can own a GitHub App"
      visibility :internal

      possible_types(
        Objects::Enterprise,
        Objects::Organization,
        Objects::User,
        Objects::DotcomAppOwnerMetadata
      )
    end
  end
end
