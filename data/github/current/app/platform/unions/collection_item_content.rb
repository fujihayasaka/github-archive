# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CollectionItemContent < Platform::Unions::Base
      description "Types that can be inside Collection Items."

      possible_types(
        Objects::CollectionUrl,
        Objects::CollectionVideo,
        Objects::Repository,
        Objects::Organization,
        Objects::User,
      )
    end
  end
end
